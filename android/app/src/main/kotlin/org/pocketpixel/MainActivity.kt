package org.pocketpixel

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** SAF and the tested Aseprite implementation are the only Android-specific parts. */
class MainActivity : FlutterActivity() {
    companion object {
        // Activity recreation must never create a second writer or reset ID
        // allocation while the previous Activity's final flush is still queued.
        private val runtime = NativeEditorRuntime()
        // Retain requests not yet drained by Flutter when an Activity recreates.
        private val externalUris = java.util.concurrent.ConcurrentLinkedQueue<ExternalProject>()
    }
    private data class ExternalProject(val uri: Uri, val flags: Int)
    private data class PickerRequest(
        val kind: String, val result: MethodChannel.Result,
        val documentId: Int, val revision: Long, val bytes: ByteArray?, val title: String,
    )

    private var restoredActivity = false
    override fun onCreate(savedInstanceState: Bundle?) {
        restoredActivity = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }
    private val sessions get() = runtime.sessions
    private val editor get() = sessions.active.engine
    private val worker get() = runtime.worker
    private val main = Handler(Looper.getMainLooper())
    private val exportFiles by lazy { ExportFiles(this, worker, main) }
    private val projectFiles by lazy { ProjectFiles(applicationContext) }
    private val documentNames by lazy { DocumentNames(applicationContext.contentResolver) }
    private val drafts get() = runtime.drafts
    private val pendingDrafts get() = runtime.pendingDrafts
    private var draftTask: ScheduledFuture<*>?
        get() = runtime.draftTask
        set(value) { runtime.draftTask = value }
    private val draftsInitialized get() = runtime.initialized
    private var pending: PickerRequest? = null
    private var revision: Long
        get() = sessions.active.revision
        set(value) { sessions.active.revision=value }
    private var externalChannel: MethodChannel? = null
    private var externalOpenError: String? = null
    @Volatile private var externalQueueError: String? = null
    private fun enqueueExternal(value: Intent?) {
        if (value == null || (value.action != Intent.ACTION_VIEW && value.action != Intent.ACTION_EDIT)) return
        val uri=value.data ?: return
        if(uri.scheme != "content" && uri.scheme != "file") return
        if(externalUris.size >= 8) {
            externalQueueError="Too many pending projects. Open the remaining files again after these finish."
            externalChannel?.invokeMethod("pending", null)
            return
        }
        externalQueueError=null
        externalUris.add(ExternalProject(uri, value.flags))
        externalChannel?.invokeMethod("pending", null)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueExternal(intent)
    }
    private fun openProject(uri: Uri, flags: Int) {
        require(sessions.documents.size < 8) { "Close a document before opening another (8 maximum)." }
        val loaded = projectFiles.read(uri)
        val target = projectFiles.writableTarget(uri, flags)
        val opened = sessions.add(loaded, documentNames.resolve(uri))
        opened.path = target?.toString()
        opened.sourceUri = uri.toString()
        changed()
    }

    private fun openExternal() {
        val request = externalUris.poll() ?: return
        externalOpenError=null
        try {
            openProject(request.uri, request.flags)
        } catch(e: Exception) { externalOpenError="Could not open project: ${e.message}" }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        externalChannel=MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pocketpixel/external")
        if(runtime.shouldEnqueueStartup(restoredActivity))enqueueExternal(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pocketpixel/editor").setMethodCallHandler(::handle)
    }
    private fun initializeDrafts() = runtime.initialize(filesDir, documentNames::refreshLegacy)
    private fun closedDrafts(): List<Map<String,Any?>> {
        val open=sessions.documents.map {it.id}.toSet()
        return drafts.summaries().filter { it["id"] !in open }
    }
    private fun state(): Map<String,Any?> {
        val available=closedDrafts()
        val saved=drafts.summaries().associateBy {it["id"] as Int}
        return sessions.state(available.isNotEmpty()) + mapOf(
            "drafts" to available,
            "lastNewWidth" to runtime.lastNewWidth, "lastNewHeight" to runtime.lastNewHeight,
            "recoveryError" to (runtime.workspaceError ?: sessions.documents.firstOrNull { it.id == sessions.activeId }?.recoveryError),
            "documents" to sessions.documents.map { session -> mapOf(
                "id" to session.id, "title" to session.title,
                "dirty" to session.engine.dirty, "active" to (session.id==sessions.activeId),
                "recoveryError" to session.recoveryError,
                "draftPending" to pendingDrafts.contains(session.id),
                "draftSavedAt" to saved[session.id]?.get("updatedAt"),
            ) },
            "externalPending" to externalUris.isNotEmpty(),
            "externalOpenError" to (externalQueueError ?: externalOpenError),
        )
    }
    private fun recoverDocuments(id: Int?) {
        val candidates=closedDrafts().filter { id==null || it["id"]==id }
        require(id==null || candidates.isNotEmpty()) { "Draft is already open or no longer available" }
        candidates.forEach { item ->
            val savedId=item["id"] as Int
            try {
                val draft=drafts.read(savedId)
                val restored=sessions.restoreDecoded(listOf(savedId to draft.document)).single()
                restored.title=draft.title
                restored.titleNeedsRefresh=draft.titleNeedsRefresh
                restored.sourceUri=draft.sourceUri
                restored.path=null // Source metadata is never a restored write grant.
                sessions.select(restored.id)
                if(savedId!=restored.id || draft.titleRefreshed) {
                    // The decoded document is already open. If migration fails,
                    // report that in state rather than failing after replacing
                    // the visible session; the legacy copy remains untouched.
                    if(persist(restored) && savedId!=restored.id) try { drafts.delete(savedId) }
                    catch(e: Exception) { restored.recoveryError="Recovered draft is safe, but its old copy could not be removed: ${e.message}" }
                }
                if(draft.fallback && restored.recoveryError==null) restored.recoveryError="The latest draft was damaged; the previous good snapshot was recovered. Save a copy now."
            } catch(e: Exception) {
                if(id!=null)throw e
                // Recover healthy entries independently. Corrupt/over-budget copies
                // stay in the picker; one bad document never consumes the others.
            }
        }
    }
    private fun execute(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try { initializeDrafts(); val value=block(); if(value !== DeferredResult) main.post { result.success(value) } }
            catch(e: Exception) { main.post { result.error("editor_error", e.message ?: e.javaClass.simpleName, null) } }
        }
    }
    private fun persist(session: EditorSession = sessions.active): Boolean {
        return try {
            drafts.write(session.id,session.title,session.sourceUri ?: session.path,session.engine.document,titleNeedsRefresh=session.titleNeedsRefresh)
            session.recoveryError=null
            true
        } catch(e: Exception) {
            session.recoveryError="Draft could not be written: ${e.message}. Save a copy now."
            false
        }
    }
    private fun flushDrafts(explicitChange: Boolean = false) {
        draftTask?.cancel(false);draftTask=null
        pendingDrafts.flush { id ->
            val session=sessions.documents.firstOrNull {it.id==id}
            session==null || persist(session)
        }
        runtime.saveWorkspace(explicitChange)
    }
    private fun scheduleDraft() {
        val now=android.os.SystemClock.elapsedRealtime()
        pendingDrafts.mark(sessions.activeId,now)
        draftTask?.cancel(false)
        draftTask=worker.schedule({flushDrafts()},pendingDrafts.delay(now),TimeUnit.MILLISECONDS)
    }
    private fun changed() { revision++;scheduleDraft() }
    private fun closeDocument(id: Int, discard: Boolean, keepDraft: Boolean, defaultText: String) {
        val session=sessions.documents.firstOrNull {it.id==id} ?: error("Document is no longer open")
        require(!session.engine.dirty || discard || keepDraft) { "Save, keep a draft, or explicitly discard this document." }
        if(keepDraft) {
            require(persist(session)) { session.recoveryError ?: "Draft could not be written" }
        }
        // Commit the closed-tab topology first. On failure the tab and its
        // snapshot remain open, so a kept draft cannot unexpectedly reopen.
        check(runtime.saveWorkspace(explicitChange = true, excluding = id)) {
            runtime.workspaceError ?: "Open tabs could not be remembered"
        }
        if (!keepDraft) try {
            drafts.delete(id)
        } catch (error: Exception) {
            // A partial deletion is repaired from the still-open model before
            // rolling back the index. Never lose the user's in-memory drawing.
            persist(session)
            runtime.saveWorkspace(explicitChange = true)
            throw error
        }
        pendingDrafts.forget(id)
        sessions.close(id,discard || keepDraft)
        sessions.initializePlaceholder(defaultText,allow=closedDrafts().isEmpty())
    }
    @Suppress("UNCHECKED_CAST")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args=call.arguments as? Map<String, Any?> ?: emptyMap()
        if (call.method == "saveExport") {
            if (pending != null) { result.error("busy", "Finish the file picker first", null); return }
            exportFiles.begin(args, result); return
        }
        if (exportFiles.busy) { result.error("busy", "Finish the export first", null); return }
        execute(result) {
            val defaultText = if(call.method in listOf("init","new","closeDocument")) defaultUserData(args) else ""
            when(call.method) {
                "init" -> sessions.initializePlaceholder(defaultText, allow = closedDrafts().isEmpty())
                "state", "listDrafts" -> Unit
                "flushDrafts" -> flushDrafts()
                "openExternal" -> openExternal()
                "exportSnapshot" -> return@execute exportSnapshot(editor.document, editor.frame, args)
                "thumbnails" -> return@execute editor.thumbnails(args)
                "copyRegion" -> return@execute copyRegion(editor.document,editor.frame,editor.layer,args)
                "frameImage" -> return@execute editor.frameImage(args)
                "previewStroke" -> return@execute editor.previewStroke(args)
                "new" -> {
                    val width = args.strictInteger("width", runtime.lastNewWidth)
                    val height = args.strictInteger("height", runtime.lastNewHeight)
                    require(width in 1..2048 && height in 1..2048) { "Use dimensions from 1 to 2048" }
                    sessions.add(newSprite(width,height,defaultText),unsaved=true)
                    runtime.lastNewWidth=width;runtime.lastNewHeight=height
                    changed()
                }
                "selectDocument" -> sessions.select(args.number("id",-1))
                "closeDocument" -> closeDocument(args.number("id",-1),args["discard"]==true,args["keepDraft"]==true,defaultText)
                "clearTagClipboard" -> sessions.clearClipboard()
                "copyTag" -> sessions.copyTag(args.number("index",-1))
                "pasteTag" -> {if(args["asNew"]==true)sessions.pasteTagAsNew() else sessions.pasteTag((args["after"] as? Number)?.toInt());changed()}
                "select" -> editor.select(args)
                "stroke" -> { editor.stroke(args); changed() }
                "edit" -> { editor.edit(args); changed() }
                "undo" -> { editor.undo(); changed() }
                "redo" -> { editor.redo(); changed() }
                "recover" -> recoverDocuments((args["id"] as? Number)?.toInt())
                "discardRecovery" -> {
                    val id=(args["id"] as? Number)?.toInt()
                    val targets=closedDrafts().filter {id==null || it["id"]==id}
                    require(id==null || targets.isNotEmpty()) { "Draft is already open or no longer available" }
                    targets.forEach {drafts.delete(it["id"] as Int)}
                }
                "open" -> return@execute requestPicker("open", result)
                "exportPng" -> {
                    val doc = editor.document
                    return@execute requestPicker("exportPng", result, Png.encode(doc.width, doc.height, doc.composite(editor.frame)))
                }
                "save", "saveAs" -> {
                    val bytes = Aseprite.write(editor.document)
                    Aseprite.read(bytes) // Validate before opening the destination for truncation.
                    persist() // A full draft store must still permit a manual save.
                    val target = sessions.active.path?.let(Uri::parse)
                    if (call.method == "save" && target != null) {
                        val output = projectFiles.outputForExisting(target)
                        if (output != null) {
                            output.use { it.write(bytes) }
                            finishSave(target, revision, sessions.active.title)
                            flushDrafts(explicitChange = true)
                            return@execute state() + ("savedProject" to sessions.active.title)
                        }
                    }
                    return@execute requestPicker("saveAs", result, bytes)
                }
                else -> error("Unknown editor method: ${call.method}")
            }
            if (call.method in listOf("new", "openExternal", "selectDocument", "closeDocument", "recover", "pasteTag")) flushDrafts(explicitChange = true)
            state()
        }
    }
    private object DeferredResult
    private fun finishSave(uri: Uri, savedRevision: Long, fallbackTitle: String) {
        val session = sessions.active
        session.path = uri.toString()
        session.sourceUri = uri.toString()
        session.title = documentNames.resolve(uri, fallbackTitle)
        session.titleNeedsRefresh = false
        if (revision == savedRevision) editor.saved()
        // Retry failed draft writes through the normal pending-draft flush.
        scheduleDraft()
    }

    private fun requestPicker(kind: String, result: MethodChannel.Result, bytes: ByteArray? = null): DeferredResult {
        val title = when (kind) {
            "saveAs" -> ProjectFiles.suggestedName(sessions.active.title)
            "exportPng" -> "sprite.png"
            else -> ""
        }
        val request = PickerRequest(kind, result, sessions.activeId, if (bytes == null) 0L else revision, bytes, title)
        main.post {
            if (pending != null || exportFiles.busy) {
                result.error("busy", "Finish the open file picker first", null)
                return@post
            }
            val intent = Intent(if (kind == "open") Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = when (kind) {
                    "open" -> "*/*"
                    "exportPng" -> "image/png"
                    else -> ProjectFiles.MIME_TYPE
                }
                if (kind != "open") putExtra(Intent.EXTRA_TITLE, title)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            pending = request
            try {
                startActivityForResult(intent, 42)
            } catch (e: Exception) {
                pending = null
                result.error("picker_error", e.message, null)
            }
        }
        return DeferredResult
    }

    @Deprecated("Android activity result callback is required by FlutterActivity's SAF bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ExportFiles.REQUEST) { exportFiles.complete(resultCode, data); return }
        if (requestCode != 42) return
        val request = pending ?: return
        pending = null
        execute(request.result) {
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) return@execute state()
            require(uri.scheme == "content") { "Choose a file from a document provider" }
            if (request.kind == "open") {
                openProject(uri, data.flags)
            } else {
                require(sessions.activeId == request.documentId) { "Active document changed while the picker was open. Try again." }
                val bytes = requireNotNull(request.bytes)
                projectFiles.openOutput(uri).use { it.write(bytes) }
                if (request.kind == "saveAs") finishSave(uri, request.revision, request.title)
            }
            if (request.kind != "exportPng" && data.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0) {
                val grants = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                try { contentResolver.takePersistableUriPermission(uri, grants) }
                catch (_: SecurityException) { /* The provider offered only session access. */ }
            }
            flushDrafts(explicitChange = true)
            if (request.kind == "saveAs") state() + ("savedProject" to sessions.active.title) else state()
        }
    }
    override fun onPause() {
        if(!worker.isShutdown)worker.execute { if(draftsInitialized)flushDrafts() }
        super.onPause()
    }
    override fun onStop() {
        if(!worker.isShutdown)worker.execute { if(draftsInitialized)flushDrafts() }
        super.onStop()
    }
    override fun onDestroy() {
        if(!worker.isShutdown)worker.execute { if(draftsInitialized)flushDrafts() }
        // The worker/model belong to the application process, not this Activity.
        // A replacement Activity reuses the queue, including this final flush.
        super.onDestroy()
    }
}

