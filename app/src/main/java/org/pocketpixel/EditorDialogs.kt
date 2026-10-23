package org.pocketpixel

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*

@Composable
internal fun TextEntry(
    title: String,
    initial: String,
    numeric: Boolean = false,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                text,
                { text = it },
                singleLine = true,
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType = if (numeric) KeyboardType.Number else KeyboardType.Text
                    ),
            )
        },
        confirmButton = { Action("Apply") { onSave(text) } },
        dismissButton = { Action("Cancel", click = onDismiss) },
    )
}

@Composable
internal fun DimensionDialog(
    title: String,
    initialW: Int,
    initialH: Int,
    onDismiss: () -> Unit,
    onSave: (Int, Int) -> Unit,
) {
    var w by remember { mutableStateOf(initialW.toString()) }
    var h by remember { mutableStateOf(initialH.toString()) }
    val wi = w.toIntOrNull()
    val hi = h.toIntOrNull()
    val valid = wi != null && hi != null && wi in 1..2048 && hi in 1..2048
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                OutlinedTextField(
                    w,
                    { w = it },
                    label = { Text("Width (1–2048)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    h,
                    { h = it },
                    label = { Text("Height (1–2048)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                if (title == "Resize")
                    Text("Top-left anchor. Pixels outside the canvas are retained in cels.")
            }
        },
        confirmButton = { Action("Apply", valid) { onSave(wi!!, hi!!) } },
        dismissButton = { Action("Cancel", click = onDismiss) },
    )
}

@Composable
internal fun ColorDialog(initial: Int, depth: Int, onDismiss: () -> Unit, onSave: (Int) -> Unit) {
    var color by remember { mutableIntStateOf(initial) }
    var hex by remember { mutableStateOf("%08X".format(initial)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Color · AARRGGBB") },
        text = {
            Column {
                Box(Modifier.fillMaxWidth().height(36.dp).background(Color(color)))
                OutlinedTextField(
                    hex,
                    {
                        hex = it
                        it.toLongOrNull(16)
                            ?.takeIf { _ -> it.length == 8 }
                            ?.let { v -> color = v.toInt() }
                    },
                    singleLine = true,
                    label = { Text("Hex") },
                )
                listOf("Red", "Green", "Blue", "Alpha").forEachIndexed { i, label ->
                    val shift = listOf(16, 8, 0, 24)[i]
                    Text("$label: ${color ushr shift and 255}")
                    Slider(
                        (color ushr shift and 255).toFloat(),
                        { v ->
                            color = (color and (255 shl shift).inv()) or (v.toInt() shl shift)
                            hex = "%08X".format(color)
                        },
                        valueRange = 0f..255f,
                    )
                }
                if (depth == 8)
                    Text(
                        "Uses the nearest existing palette entry; alpha zero selects the transparent index."
                    )
                if (depth == 16) Text("RGB is converted to grayscale; alpha is retained.")
            }
        },
        confirmButton = { Action("Use color") { onSave(color) } },
        dismissButton = { Action("Cancel", click = onDismiss) },
    )
}

@Composable
internal fun UserDataDialog(
    e: Editor,
    onDismiss: () -> Unit,
    onSave: (Int, String, ByteArray?) -> Unit,
) {
    var target by remember { mutableIntStateOf(0) }
    val labels =
        listOf("Sprite", "Layer: ${e.doc.layers[e.layer].name}", "Cel: frame ${e.frame + 1}") +
            e.doc.tags.map { "Tag: ${it.name}" }
    val old =
        when (target) {
            0 -> e.doc.data
            1 -> e.doc.layers[e.layer].data
            2 -> e.doc.frames[e.frame].cels[e.layer]?.data
            else -> e.doc.tags[target - 3].data
        }
    var text by remember(target) { mutableStateOf(old?.text ?: "") }
    var properties by remember(target) { mutableStateOf(UserProperties.read(old?.properties)) }
    var propertyChanged by remember(target) { mutableStateOf(false) }
    var key by remember(target) { mutableStateOf("") }
    var value by remember(target) { mutableStateOf("") }
    var type by remember(target) { mutableIntStateOf(6) }
    var error by remember(target) { mutableStateOf<String?>(null) }
    val existing = properties.firstOrNull { it.name == key }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("User data") },
        text = {
            Column(Modifier.heightIn(max = 500.dp).verticalScroll(rememberScrollState())) {
                Row(Modifier.horizontalScroll(rememberScrollState())) {
                    labels.forEachIndexed { i, label ->
                        FilterChip(
                            selected = target == i,
                            onClick = { target = i },
                            label = { Text(label) },
                            modifier = Modifier.padding(2.dp),
                        )
                    }
                }
                OutlinedTextField(
                    text,
                    { if (it.toByteArray().size <= 65535) text = it },
                    label = { Text("Text / JSON / game attributes") },
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                )
                Text(
                    "Text is stored verbatim. Example: {\"strength\": 12}",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (old?.color != null) Text("Existing user data color is preserved.")
                Text(
                    "Typed properties",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(top = 12.dp),
                )
                properties.forEach { p ->
                    Action("${p.name}: ${p.text()}", p.editable) {
                        key = p.name
                        value = p.text()
                        type = p.type
                        error = null
                    }
                }
                OutlinedTextField(
                    key,
                    { key = it },
                    label = { Text("Property name, e.g. strength") },
                    singleLine = true,
                )
                OutlinedTextField(value, { value = it }, label = { Text("Value") })
                if (existing == null)
                    Row(Modifier.horizontalScroll(rememberScrollState())) {
                        listOf(6 to "Integer", 12 to "Decimal", 13 to "Text", 1 to "Boolean")
                            .forEach { (t, label) ->
                                FilterChip(
                                    selected = type == t,
                                    onClick = { type = t },
                                    label = { Text(label) },
                                    modifier = Modifier.padding(2.dp),
                                )
                            }
                    }
                else Text("Existing type ${existing.type} is retained.")
                Row {
                    Action(
                        "Set property",
                        key.isNotBlank() && (existing == null || existing.editable),
                    ) {
                        try {
                            val property =
                                (existing ?: Property(key, type, ByteArray(0))).withText(value)
                            require(key.toByteArray().size <= 65535) { "Property name is too long" }
                            properties =
                                if (existing == null) properties + property
                                else properties.map { if (it === existing) property else it }
                            propertyChanged = true
                            key = ""
                            value = ""
                            type = 6
                            error = null
                        } catch (t: Exception) {
                            error = t.message ?: "Invalid property value"
                        }
                    }
                    Action("Remove", existing != null) {
                        properties = properties.filter { it !== existing }
                        propertyChanged = true
                        key = ""
                        value = ""
                    }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Text(
                    "Tap Set property before Save data. Nested values, vectors, and geometry are preserved read-only.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        confirmButton = {
            Action("Save data") {
                onSave(
                    target,
                    text,
                    if (propertyChanged) UserProperties.write(properties) else old?.properties,
                )
            }
        },
        dismissButton = { Action("Cancel", click = onDismiss) },
    )
}

@Composable
internal fun TagDialog(e: Editor, selected: Int, onDismiss: () -> Unit, select: (Int) -> Unit) {
    var name by remember { mutableStateOf("") }
    var from by remember { mutableStateOf("1") }
    var to by remember { mutableStateOf(e.doc.frames.size.toString()) }
    val first = from.toIntOrNull() ?: 0
    val last = to.toIntOrNull() ?: 0
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Animation tags") },
        text = {
            Column {
                Action(if (selected == -1) "✓ All frames" else "All frames") { select(-1) }
                Column(Modifier.heightIn(max = 160.dp).verticalScroll(rememberScrollState())) {
                    e.doc.tags.forEachIndexed { i, t ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Action(
                                "${if (i == selected) "✓ " else ""}${t.name} (${t.from + 1}–${t.to + 1})"
                            ) {
                                select(i)
                            }
                            Action("Delete") { e.edit { tags.removeAt(i) } }
                        }
                    }
                }
                OutlinedTextField(name, { name = it }, label = { Text("New tag name") })
                Row {
                    OutlinedTextField(
                        from,
                        { from = it },
                        label = { Text("From") },
                        modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    OutlinedTextField(
                        to,
                        { to = it },
                        label = { Text("To") },
                        modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                }
                Action(
                    "Add forward tag",
                    name.isNotBlank() &&
                        first in 1..e.doc.frames.size &&
                        last in first..e.doc.frames.size,
                ) {
                    e.edit {
                        tags.add(Tag(first - 1, last - 1, 0, 0, byteArrayOf(100, 100, 100), name))
                    }
                    name = ""
                }
            }
        },
        confirmButton = { Action("Close", click = onDismiss) },
    )
}
