package org.pocketpixel

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.util.AtomicFile
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class Editor : ViewModel() {
    val recoveryMutex = Mutex()
    var doc by mutableStateOf(Document.create())
    var frame by mutableIntStateOf(0)
    var layer by mutableIntStateOf(0)
    var revision by mutableIntStateOf(0)
    var dirty by mutableStateOf(false)
    var busy by mutableStateOf(false)
    var playing by mutableStateOf(false)
    var color by mutableIntStateOf(0xff000000.toInt())
    var uri: Uri? = null
    val history = History()

    fun changed() {
        dirty = true
        revision++
    }

    fun edit(block: Document.() -> Unit) {
        history.push(doc)
        doc.block()
        changed()
    }

    fun replace(d: Document, u: Uri? = null, unsaved: Boolean = false) {
        doc = d
        uri = u
        frame = 0
        layer =
            d.layers.indexOfLast { it.visible && it.flags and 2 != 0 }.takeIf { it >= 0 }
                ?: d.layers.indexOfLast { it.visible }.coerceAtLeast(0)
        history.clear()
        dirty = unsaved
        revision++
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var editor: Editor

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        editor = ViewModelProvider(this)[Editor::class.java]
        setContent {
            MaterialTheme(
                colorScheme =
                    darkColorScheme(primary = Color(0xffb9c3ff), surface = Color(0xff1b1c23))
            ) {
                Surface { PocketEditor(editor) }
            }
        }
    }
}

@Composable
internal fun Action(label: String, enabled: Boolean = true, click: () -> Unit) {
    TextButton(
        onClick = click,
        enabled = enabled,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
        modifier = Modifier.heightIn(min = 44.dp),
    ) {
        Text(label, maxLines = 1)
    }
}

@Composable
fun PocketEditor(e: Editor) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val recovery = remember { AtomicFile(File(context.filesDir, "recovery.aseprite")) }
    var message by remember { mutableStateOf<String?>(null) }
    var dialog by remember { mutableStateOf<String?>(null) }
    var discard by remember { mutableStateOf<(() -> Unit)?>(null) }
    var recoveryPrompt by remember { mutableStateOf(false) }
    var tool by remember { mutableStateOf(Tool.Pencil) }
    var brush by remember { mutableIntStateOf(1) }
    var grid by remember { mutableStateOf(false) }
    var onion by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(false) }
    var panel by remember { mutableStateOf("Layers") }
    var view by remember { mutableStateOf<PixelView?>(null) }
    var tagIndex by remember { mutableIntStateOf(-1) }
    fun report(t: Throwable) {
        message = t.message ?: t.javaClass.simpleName
    }
    fun safe(block: () -> Unit) {
        try {
            block()
        } catch (t: Exception) {
            report(t)
        }
    }
    fun abandon(action: () -> Unit) {
        e.playing = false
        if (e.dirty) discard = action else action()
    }
    suspend fun clearRecovery() {
        e.recoveryMutex.withLock { withContext(Dispatchers.IO) { recovery.delete() } }
    }
    suspend fun persist(snapshot: Document) {
        e.recoveryMutex.withLock {
            withContext(Dispatchers.IO) {
                val bytes = Aseprite.write(snapshot)
                val stream = recovery.startWrite()
                try {
                    stream.write(bytes)
                    recovery.finishWrite(stream)
                } catch (t: Exception) {
                    recovery.failWrite(stream)
                    throw t
                }
            }
        }
    }
    fun saveTo(uri: Uri) {
        e.playing = false
        e.busy = true
        val snapshot = e.doc.copyDeep()
        val version = e.revision
        scope.launch {
            try {
                val bytes =
                    withContext(Dispatchers.Default) {
                        Aseprite.write(snapshot).also { Aseprite.read(it) }
                    }
                // A recovery copy survives provider write failures, including providers without
                // atomic replace.
                persist(snapshot)
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                        ?: error("Document provider did not open a writable stream")
                }
                e.uri = uri
                if (e.revision == version) {
                    e.dirty = false
                    clearRecovery()
                }
                message = "Saved"
            } catch (t: Exception) {
                report(t)
            } finally {
                e.busy = false
            }
        }
    }
    val saveAs =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream")
        ) { uri ->
            if (uri != null) saveTo(uri)
        }
    val export =
        rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/png")) { uri
            ->
            if (uri != null) {
                e.busy = true
                val snapshot = e.doc.copyDeep()
                val frame = e.frame
                scope.launch {
                    try {
                        withContext(Dispatchers.Default) {
                            val b =
                                Bitmap.createBitmap(
                                    snapshot.composite(frame),
                                    snapshot.width,
                                    snapshot.height,
                                    Bitmap.Config.ARGB_8888,
                                )
                            try {
                                context.contentResolver.openOutputStream(uri, "wt")?.use {
                                    check(b.compress(Bitmap.CompressFormat.PNG, 100, it))
                                } ?: error("Cannot export PNG")
                            } finally {
                                b.recycle()
                            }
                        }
                        message = "PNG exported"
                    } catch (t: Exception) {
                        report(t)
                    } finally {
                        e.busy = false
                    }
                }
            }
        }
    val open =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) {
                e.busy = true
                scope.launch {
                    try {
                        val d =
                            withContext(Dispatchers.IO) {
                                val bytes =
                                    context.contentResolver.openInputStream(uri)?.use {
                                        readLimited(it)
                                    } ?: error("Cannot read document")
                                Aseprite.read(bytes)
                            }
                        try {
                            context.contentResolver.takePersistableUriPermission(
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                            )
                        } catch (_: SecurityException) {}
                        e.replace(d, uri)
                        clearRecovery()
                        view?.fit()
                    } catch (t: Exception) {
                        report(t)
                    } finally {
                        e.busy = false
                    }
                }
            }
        }
    LaunchedEffect(Unit) { if (recovery.baseFile.exists() && !e.dirty) recoveryPrompt = true }
    LaunchedEffect(e.revision, e.dirty) {
        if (e.dirty) {
            delay(450)
            try {
                persist(e.doc.copyDeep())
            } catch (t: Exception) {
                message = "Recovery failed: ${t.message}"
            }
        }
    }
    LaunchedEffect(e.playing, tagIndex) {
        var direction = 1
        var repetitions = 0
        while (e.playing) {
            delay(e.doc.frames[e.frame].duration.toLong().coerceAtLeast(1))
            val tag = e.doc.tags.getOrNull(tagIndex)
            val from = tag?.from ?: 0
            val to = tag?.to ?: e.doc.frames.lastIndex
            val mode = tag?.direction ?: 0
            if (mode in 0..1) {
                val next = if (mode == 0) e.frame + 1 else e.frame - 1
                val wrapped = next !in from..to
                if (wrapped) repetitions++
                e.frame =
                    if (wrapped) {
                        if (mode == 0) from else to
                    } else next
            } else {
                if (mode == 3 && repetitions == 0 && e.frame == to) direction = -1
                var next = e.frame + direction
                if (next !in from..to) {
                    direction = -direction
                    next = if (from == to) from else e.frame + direction
                    repetitions++
                }
                e.frame = next
            }
            if (tag != null && tag.repeat > 0 && repetitions >= tag.repeat) e.playing = false
            e.revision++
        }
    }
    BackHandler(enabled = e.dirty || e.busy) {
        if (!e.busy) discard = { (context as? android.app.Activity)?.finish() }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Action("New", !e.busy) { abandon { dialog = "New" } }
                Action("Open", !e.busy) { abandon { open.launch(arrayOf("*/*")) } }
                Action(if (e.dirty) "Save •" else "Save", !e.busy) {
                    safe {
                        if (e.uri == null) saveAs.launch("sprite.aseprite") else saveTo(e.uri!!)
                    }
                }
                Action("↶", !e.busy && !e.playing) {
                    e.history.undo(e.doc)?.let {
                        e.doc = it
                        e.frame = e.frame.coerceAtMost(it.frames.lastIndex)
                        e.layer = e.layer.coerceAtMost(it.layers.lastIndex)
                        e.changed()
                    }
                }
                Action("↷", !e.busy && !e.playing) {
                    e.history.redo(e.doc)?.let {
                        e.doc = it
                        e.frame = e.frame.coerceAtMost(it.frames.lastIndex)
                        e.layer = e.layer.coerceAtMost(it.layers.lastIndex)
                        e.changed()
                    }
                }
                Action("More", !e.busy) {
                    e.playing = false
                    dialog = "More"
                }
            }
            Tool.entries.chunked(4).forEach { row ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    row.forEach { t ->
                        FilterChip(
                            selected = tool == t,
                            onClick = {
                                e.playing = false
                                tool = t
                            },
                            label = { Text(t.name) },
                            modifier = Modifier.weight(1f).testTag("tool-${t.name}"),
                        )
                    }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(horizontal = 10.dp),
            ) {
                Box(
                    Modifier.size(30.dp)
                        .background(Color(e.color))
                        .border(1.dp, Color.White)
                        .clickable { dialog = "Color" }
                )
                Text("  $brush px", modifier = Modifier.width(66.dp))
                Slider(
                    brush.toFloat(),
                    { brush = it.toInt() },
                    valueRange = 1f..16f,
                    steps = 14,
                    modifier = Modifier.weight(1f),
                )
                Action("Fit") { view?.fit() }
                Action(if (grid) "Grid ✓" else "Grid") { grid = !grid }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                AndroidView(
                    factory = { ctx ->
                        PixelView(ctx).also {
                            view = it
                            it.editor = e
                            it.onChanged = { e.revision++ }
                            it.onError = { message = it }
                        }
                    },
                    update = {
                        it.editor = e
                        it.tool = tool
                        it.color = e.color
                        it.brush = brush
                        it.grid = grid
                        it.onion = onion
                        e.revision
                        it.refresh()
                    },
                    modifier = Modifier.fillMaxSize().testTag("pixelCanvas"),
                )
                Text(
                    "$tool · ${e.doc.layers[e.layer].name} · ${e.doc.width} × ${e.doc.height} · ${when(e.doc.depth){8->"Indexed"
16->"Gray + alpha"
else->"RGBA"}}",
                    style = MaterialTheme.typography.labelSmall,
                    modifier =
                        Modifier.align(Alignment.TopStart)
                            .padding(8.dp)
                            .background(Color(0xaa17191e)),
                )
                if (e.busy) CircularProgressIndicator(Modifier.align(Alignment.Center))
            }
            Row(
                Modifier.fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Action("Color") { dialog = "Color" }
                val palette =
                    if (e.doc.depth == 8) e.doc.frames[e.frame].palette.toList()
                    else if (e.doc.depth == 16)
                        (0..15).map { 0xff000000.toInt() or (it * 17 * 0x010101) }
                    else e.doc.palette
                palette.forEachIndexed { i, c ->
                    Box(
                        Modifier.size(36.dp)
                            .background(Color(c))
                            .border(
                                if (e.color == c) 3.dp else 1.dp,
                                if (e.color == c) MaterialTheme.colorScheme.primary else Color.Gray,
                            )
                            .clickable {
                                e.color =
                                    if (e.doc.depth == 8 && i == e.doc.transparentIndex) 0 else c
                            }
                    )
                }
            }
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Action(if (e.playing) "Stop" else "Play", !e.busy) {
                    e.playing = !e.playing
                    if (e.playing) {
                        val t = e.doc.tags.getOrNull(tagIndex)
                        if (t != null)
                            e.frame = if (t.direction == 1 || t.direction == 3) t.to else t.from
                    }
                }
                Action(
                    "${e.frame+1}/${e.doc.frames.size} · ${e.doc.frames[e.frame].duration} ms",
                    !e.playing,
                ) {
                    dialog = "Duration"
                }
                Action(if (expanded) "Hide panel" else "Layers / Frames") { expanded = !expanded }
            }
            if (expanded)
                Column(Modifier.fillMaxWidth().heightIn(max = 230.dp)) {
                    Row {
                        listOf("Layers", "Frames").forEach { s ->
                            Action(if (panel == s) "[$s]" else s) { panel = s }
                        }
                        Action("Data", !e.playing) { dialog = "User data" }
                    }
                    if (panel == "Layers") {
                        Row(Modifier.horizontalScroll(rememberScrollState())) {
                            Action("+ Layer", !e.playing) {
                                safe {
                                    e.edit {
                                        layers.add(Layer("Layer ${layers.size+1}"))
                                        frames.forEach { it.cels.add(null) }
                                    }
                                    e.layer = e.doc.layers.lastIndex
                                }
                            }
                            Action("Rename", !e.playing) { dialog = "Rename" }
                            Action("↑", !e.playing && e.layer < e.doc.layers.lastIndex) {
                                safe {
                                    e.edit {
                                        val i = e.layer
                                        java.util.Collections.swap(layers, i, i + 1)
                                        frames.forEach {
                                            java.util.Collections.swap(it.cels, i, i + 1)
                                        }
                                    }
                                    e.layer++
                                }
                            }
                            Action("↓", !e.playing && e.layer > 0) {
                                safe {
                                    e.edit {
                                        val i = e.layer
                                        java.util.Collections.swap(layers, i, i - 1)
                                        frames.forEach {
                                            java.util.Collections.swap(it.cels, i, i - 1)
                                        }
                                    }
                                    e.layer--
                                }
                            }
                            Action("Delete", !e.playing && e.doc.layers.size > 1) {
                                dialog = "Delete layer"
                            }
                        }
                        LazyColumn {
                            items(e.doc.layers.indices.reversed().toList()) { i ->
                                Row(
                                    Modifier.fillMaxWidth()
                                        .background(
                                            if (i == e.layer)
                                                MaterialTheme.colorScheme.secondaryContainer
                                            else Color.Transparent
                                        )
                                        .clickable {
                                            e.layer = i
                                            e.revision++
                                        },
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Checkbox(
                                        e.doc.layers[i].visible,
                                        { e.edit { layers[i].visible = it } },
                                        enabled = !e.playing,
                                    )
                                    Text(e.doc.layers[i].name, modifier = Modifier.weight(1f))
                                    Action("${e.doc.layers[i].opacity*100/255}%", !e.playing) {
                                        e.layer = i
                                        dialog = "Opacity"
                                    }
                                }
                            }
                        }
                    } else {
                        Row(Modifier.horizontalScroll(rememberScrollState())) {
                            Action("+ Frame", !e.playing) {
                                safe {
                                    e.edit { addFrame(e.frame, false) }
                                    e.frame++
                                }
                            }
                            Action("Duplicate", !e.playing) {
                                safe {
                                    e.edit { addFrame(e.frame, true) }
                                    e.frame++
                                }
                            }
                            Action("Delete", !e.playing && e.doc.frames.size > 1) {
                                dialog = "Delete frame"
                            }
                            Action(if (onion) "Onion ✓" else "Onion") { onion = !onion }
                            Action("Tags", !e.playing) { dialog = "Tags" }
                        }
                        Row(Modifier.horizontalScroll(rememberScrollState())) {
                            e.doc.frames.indices.forEach { i ->
                                FilterChip(
                                    selected = e.frame == i,
                                    onClick = {
                                        e.playing = false
                                        e.frame = i
                                        e.revision++
                                    },
                                    label = { Text("${i+1} · ${e.doc.frames[i].duration}") },
                                    modifier = Modifier.padding(3.dp),
                                )
                            }
                        }
                    }
                }
        }
        if (e.busy)
            Box(Modifier.fillMaxSize().background(Color(0x6617191e)).clickable {}) {
                CircularProgressIndicator(Modifier.align(Alignment.Center))
            }
    }
    if (message != null)
        AlertDialog(
            onDismissRequest = { message = null },
            title = { Text("Pocket Pixel") },
            text = { Text(message!!) },
            confirmButton = { Action("OK") { message = null } },
        )
    if (discard != null)
        AlertDialog(
            onDismissRequest = { discard = null },
            title = { Text("Discard unsaved changes?") },
            text = { Text("Save first if you want to keep your edits.") },
            confirmButton = {
                Action("Discard") {
                    val action = discard
                    discard = null
                    e.dirty = false
                    scope.launch { clearRecovery() }
                    action?.invoke()
                }
            },
            dismissButton = { Action("Cancel") { discard = null } },
        )
    if (recoveryPrompt)
        AlertDialog(
            onDismissRequest = { recoveryPrompt = false },
            title = { Text("Recover unsaved sprite?") },
            text = {
                Text("A local recovery copy is available. It will open as an unsaved document.")
            },
            confirmButton = {
                Action("Recover") {
                    recoveryPrompt = false
                    e.busy = true
                    scope.launch {
                        try {
                            val d =
                                withContext(Dispatchers.IO) {
                                    recovery.openRead().use { Aseprite.read(readLimited(it)) }
                                }
                            e.replace(d, unsaved = true)
                        } catch (t: Exception) {
                            report(t)
                        } finally {
                            e.busy = false
                        }
                    }
                }
            },
            dismissButton = {
                Action("Discard") {
                    recoveryPrompt = false
                    scope.launch { clearRecovery() }
                }
            },
        )
    when (dialog) {
        "More" ->
            AlertDialog(
                onDismissRequest = { dialog = null },
                title = { Text("Document") },
                text = {
                    Column {
                        Action("Save As") {
                            dialog = null
                            saveAs.launch("sprite.aseprite")
                        }
                        Action("Export current frame PNG") {
                            dialog = null
                            export.launch("sprite.png")
                        }
                        Action("Resize canvas") { dialog = "Resize" }
                        Action("Flip horizontal (active cel)", !e.playing) {
                            safe {
                                e.edit {
                                    val c = editable(e.frame, e.layer)
                                    for (y in 0 until c.height) for (x in 0 until c.width / 2) {
                                        val i = y * c.width + x
                                        val j = y * c.width + c.width - 1 - x
                                        val tmp = c.pixels[i]
                                        c.pixels[i] = c.pixels[j]
                                        c.pixels[j] = tmp
                                    }
                                    c.x = width - c.x - c.width
                                }
                            }
                            dialog = null
                        }
                        Action("Flip vertical (active cel)", !e.playing) {
                            safe {
                                e.edit {
                                    val c = editable(e.frame, e.layer)
                                    for (y in 0 until c.height / 2) for (x in 0 until c.width) {
                                        val i = y * c.width + x
                                        val j = (c.height - 1 - y) * c.width + x
                                        val tmp = c.pixels[i]
                                        c.pixels[i] = c.pixels[j]
                                        c.pixels[j] = tmp
                                    }
                                    c.y = height - c.y - c.height
                                }
                            }
                            dialog = null
                        }
                        Action("User data") { dialog = "User data" }
                    }
                },
                confirmButton = { Action("Close") { dialog = null } },
            )
        "New",
        "Resize" -> {
            val mode = dialog!!
            DimensionDialog(mode, e.doc.width, e.doc.height, onDismiss = { dialog = null }) { w, h
                ->
                safe {
                    if (mode == "New") {
                        e.replace(Document.create(w, h), unsaved = true)
                    } else {
                        e.edit {
                            width = w
                            height = h
                        }
                    }
                    view?.fit()
                    dialog = null
                }
            }
        }
        "Rename" ->
            TextEntry("Layer name", e.doc.layers[e.layer].name, onDismiss = { dialog = null }) { v
                ->
                safe {
                    e.edit { layers[e.layer].name = v }
                    dialog = null
                }
            }
        "Duration" ->
            TextEntry(
                "Frame duration (1–65535 ms)",
                e.doc.frames[e.frame].duration.toString(),
                numeric = true,
                onDismiss = { dialog = null },
            ) { v ->
                val n = v.toIntOrNull()
                if (n != null && n in 1..65535) {
                    e.edit { frames[e.frame].duration = n }
                    dialog = null
                }
            }
        "Opacity" ->
            TextEntry(
                "Layer opacity (0–255)",
                e.doc.layers[e.layer].opacity.toString(),
                numeric = true,
                onDismiss = { dialog = null },
            ) { v ->
                val n = v.toIntOrNull()
                if (n != null && n in 0..255) {
                    e.edit { layers[e.layer].opacity = n }
                    dialog = null
                }
            }
        "Color" ->
            ColorDialog(e.color, e.doc.depth, onDismiss = { dialog = null }) {
                e.color = it
                dialog = null
            }
        "Delete layer",
        "Delete frame" -> {
            val layer = dialog == "Delete layer"
            AlertDialog(
                onDismissRequest = { dialog = null },
                title = {
                    Text(if (layer) "Delete layer and its cels?" else "Delete frame and its data?")
                },
                confirmButton = {
                    Action("Delete") {
                        safe {
                            e.edit {
                                if (layer) {
                                    layers.removeAt(e.layer)
                                    frames.forEach { it.cels.removeAt(e.layer) }
                                } else {
                                    removeFrame(e.frame)
                                }
                            }
                            e.layer = e.layer.coerceAtMost(e.doc.layers.lastIndex)
                            e.frame = e.frame.coerceAtMost(e.doc.frames.lastIndex)
                            dialog = null
                        }
                    }
                },
                dismissButton = { Action("Cancel") { dialog = null } },
            )
        }
        "User data" ->
            UserDataDialog(e, onDismiss = { dialog = null }) { target, text, properties ->
                safe {
                    e.edit {
                        val old =
                            when (target) {
                                0 -> data
                                1 -> layers[e.layer].data
                                2 -> frames[e.frame].cels[e.layer]?.data
                                else -> tags[target - 3].data
                            }
                        val updated = (old ?: UserData()).copy(text = text, properties = properties)
                        when (target) {
                            0 -> data = updated
                            1 -> layers[e.layer].data = updated
                            2 -> {
                                if (frames[e.frame].cels[e.layer] == null)
                                    editable(e.frame, e.layer)
                                frames[e.frame].cels[e.layer]!!.data = updated
                            }
                            else -> tags[target - 3].data = updated
                        }
                    }
                    dialog = null
                }
            }
        "Tags" ->
            TagDialog(
                e,
                tagIndex,
                onDismiss = { dialog = null },
                select = {
                    tagIndex = it
                    dialog = null
                },
            )
    }
}

private fun readLimited(input: java.io.InputStream): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val n = input.read(buffer)
        if (n < 0) break
        require(out.size() + n <= Aseprite.MAX_FILE) { "File exceeds 64 MiB" }
        out.write(buffer, 0, n)
    }
    return out.toByteArray()
}
