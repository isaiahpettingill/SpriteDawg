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
        private val externalUris = java.util.concurrent.ConcurrentLinkedQueue<Uri>()
    }
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
    private val documentNames by lazy { DocumentNames(applicationContext.contentResolver) }
    private val drafts get() = runtime.drafts
    private val pendingDrafts get() = runtime.pendingDrafts
    private var draftTask: ScheduledFuture<*>?
        get() = runtime.draftTask
        set(value) { runtime.draftTask = value }
    private val draftsInitialized get() = runtime.initialized
    private var currentUri: Uri?
        get() = sessions.active.path?.let(Uri::parse)
        set(value) { sessions.active.path=value?.toString() }
    private var pending: MethodChannel.Result? = null
    private var pendingKind = ""
    private var pendingBytes: ByteArray? = null
    private var pendingRevision = 0L
    private var revision: Long
        get() = sessions.active.revision
        set(value) { sessions.active.revision=value }
    private var pendingDocument = 0
    private var externalChannel: MethodChannel? = null
    private var externalOpenError: String? = null
    @Volatile private var externalQueueError: String? = null
    private fun enqueueExternal(value: Intent?) {
        if(value?.action != Intent.ACTION_VIEW) return
        val uri=value.data ?: return
        if(uri.scheme != "content" && uri.scheme != "file") return
        if(externalUris.size >= 8) {
            externalQueueError="Too many pending projects. Open the remaining files again after these finish."
            externalChannel?.invokeMethod("pending", null)
            return
        }
        externalQueueError=null
        externalUris.add(uri)
        // VIEW grants are transient; decode while this activity owns the grant.
        // Save As avoids retaining unnecessary provider access.
        externalChannel?.invokeMethod("pending", null)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueExternal(intent)
    }
    private fun openExternal() {
        val uri=externalUris.poll() ?: return
        externalOpenError=null
        try {
            require(sessions.documents.size < 8) { "Close a document before opening another (8 maximum)." }
            val loaded=contentResolver.openInputStream(uri)?.use { stream ->
                val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(65536)
                while(true) {val n=stream.read(buffer);if(n<0)break;require(out.size()+n<=Aseprite.MAX_FILE) {"File exceeds the 64 MiB safety limit"};out.write(buffer,0,n)}
                Aseprite.read(out.toByteArray())
            } ?: error("The provider could not read this project")
            val opened=sessions.add(loaded, documentNames.resolve(uri))
            // VIEW commonly grants read-only access. Saving always asks for a destination.
            opened.path=null
            opened.sourceUri=uri.toString()
            changed()
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
    private fun flushDrafts() {
        draftTask?.cancel(false);draftTask=null
        pendingDrafts.flush { id ->
            val session=sessions.documents.firstOrNull {it.id==id}
            session==null || persist(session)
        }
    }
    private fun scheduleDraft() {
        val now=android.os.SystemClock.elapsedRealtime()
        pendingDrafts.mark(sessions.activeId,now)
        draftTask?.cancel(false)
        draftTask=worker.schedule({flushDrafts()},pendingDrafts.delay(now),TimeUnit.MILLISECONDS)
    }
    private fun changed() { revision++;scheduleDraft() }
    private fun clearDraft(session: EditorSession = sessions.active) {
        // Cancellation is ordered with all snapshots on this same worker.
        pendingDrafts.forget(session.id)
        try { drafts.delete(session.id);session.recoveryError=null }
        catch(e: Exception) { session.recoveryError="Saved project is safe, but its old draft could not be removed: ${e.message}" }
    }
    private fun closeDocument(id: Int, discard: Boolean, keepDraft: Boolean, defaultText: String) {
        val session=sessions.documents.firstOrNull {it.id==id} ?: error("Document is no longer open")
        require(!session.engine.dirty || discard || keepDraft) { "Save, keep a draft, or explicitly discard this document." }
        if(keepDraft) {
            require(persist(session)) { session.recoveryError ?: "Draft could not be written" }
        } else {
            // Do not close if explicit removal fails: it would promise a discard
            // while leaving a recoverable copy behind.
            drafts.delete(id)
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
        if (call.method in listOf("open","saveAs","exportPng")) { launchPicker(call.method,result); return }
        execute(result) {
            val defaultText = if(call.method in listOf("init","new","closeDocument")) defaultUserData(args) else ""
            when(call.method) {
                "init" -> sessions.initializePlaceholder(defaultText, allow = closedDrafts().isEmpty())
                "state", "listDrafts" -> Unit
                "flushDrafts" -> flushDrafts()
                "openExternal" -> openExternal()
                "exportSnapshot" -> return@execute exportSnapshot(editor.document, editor.frame, args)
                "thumbnails" -> return@execute editor.thumbnails(args)
                "frameImage" -> return@execute editor.frameImage(args)
                "previewStroke" -> return@execute editor.previewStroke(args)
                "new" -> { sessions.add(newSprite(args.number("width",32),args.number("height",32),defaultText),unsaved=true); changed() }
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
                "save" -> {
                    val uri=currentUri
                    if(uri==null) { main.post { launchPicker("saveAs",result) }; return@execute DeferredResult }
                    writeDocument(uri)
                }
                else -> error("Unknown editor method: ${call.method}")
            }
            state()
        }
    }
    private object DeferredResult
    private fun rememberSaveTarget(uri: Uri) {
        val session = sessions.active
        currentUri = uri
        session.sourceUri = uri.toString()
        session.title = documentNames.resolve(uri, if (session.titleNeedsRefresh) "Opened document" else session.title)
        session.titleNeedsRefresh = false
    }
    private fun writeDocument(uri: Uri) {
        val bytes=Aseprite.write(editor.document)
        Aseprite.read(bytes) // Validate before opening any destination for truncation.
        persist() // Best effort; a full draft store must not prevent manual Save.
        contentResolver.openOutputStream(uri,"wt")?.use { it.write(bytes); it.flush() } ?: error("The document provider refused this file. Use Save As.")
        editor.saved(); rememberSaveTarget(uri); clearDraft()
    }
    private fun launchPicker(kind: String,result: MethodChannel.Result) {
        if(pending!=null) { result.error("busy","Finish the open file picker first",null); return }
        pending=result; pendingKind=kind;pendingDocument=sessions.activeId
        if(kind=="open") {
            val intent=Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="*/*"; addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }
            try { startActivityForResult(intent,42) } catch(e: Exception) { pending=null; result.error("picker_error",e.message,null) }
        } else {
            worker.execute {
                try {
                    initializeDrafts()
                    pendingBytes=if(kind=="exportPng") {
                        val d=editor.document
                        Png.encode(d.width,d.height,d.composite(editor.frame))
                    } else { Aseprite.write(editor.document).also { Aseprite.read(it); persist() } }
                    pendingRevision=revision
                    main.post {
                        val intent=Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type=if(kind=="exportPng") "image/png" else "application/octet-stream"; putExtra(Intent.EXTRA_TITLE,if(kind=="exportPng") "sprite.png" else "sprite.aseprite"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }
                        try { startActivityForResult(intent,42) } catch(e: Exception) { pending=null; pendingBytes=null; result.error("picker_error",e.message,null) }
                    }
                } catch(e: Exception) { main.post { pending=null; pendingBytes=null; result.error("save_error",e.message,null) } }
            }
        }
    }
    @Deprecated("Android activity result callback is required by FlutterActivity's SAF bridge")
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode == ExportFiles.REQUEST) { exportFiles.complete(resultCode, data); return }
        if(requestCode!=42) return
        val result=pending ?: return
        val kind=pendingKind; val bytes=pendingBytes; val snapshotRevision=pendingRevision; val snapshotDocument=pendingDocument
        pending=null; pendingBytes=null
        execute(result) {
            require(sessions.activeId==snapshotDocument) { "Active document changed while file picker was open. Try again." }
            val uri=data?.data
            if(resultCode==RESULT_OK && uri!=null) {
                try { contentResolver.takePersistableUriPermission(uri,((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))) } catch(_: SecurityException) { /* A provider may offer only this session. */ }
                if(kind=="open") {
                    val loaded=contentResolver.openInputStream(uri)?.use { stream ->
                        val out=java.io.ByteArrayOutputStream(); val buffer=ByteArray(65536)
                        while(true) { val n=stream.read(buffer); if(n<0) break; require(out.size()+n<=Aseprite.MAX_FILE) { "File exceeds the 64 MiB safety limit" }; out.write(buffer,0,n) }
                        Aseprite.read(out.toByteArray())
                    } ?: error("The document provider could not read this file")
                    val opened=sessions.add(loaded, documentNames.resolve(uri))
                    opened.path=uri.toString();opened.sourceUri=uri.toString();changed()
                } else {
                    requireNotNull(bytes)
                    contentResolver.openOutputStream(uri,"wt")?.use { it.write(bytes); it.flush() } ?: error("The document provider refused this file")
                    if(kind=="saveAs") {
                        rememberSaveTarget(uri)
                        if(revision==snapshotRevision) { editor.saved(); clearDraft() }
                        else scheduleDraft() // Include the new name/source in the newer unsaved draft.
                    }
                }
            }
            state()
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
