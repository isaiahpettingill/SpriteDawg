package org.pocketpixel

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** SAF and the tested Aseprite implementation are the only Android-specific parts. */
class MainActivity : FlutterActivity() {
    private val sessions = EditorSessions()
    private val editor get() = sessions.active.engine
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val recovery get() = AtomicFile(File(filesDir,"recovery-${sessions.activeId}.aseprite"))
    private var currentUri: Uri?
        get() = sessions.active.path?.let(Uri::parse)
        set(value) { sessions.active.path=value?.toString() }
    private var startupRecovery = false
    private var pending: MethodChannel.Result? = null
    private var pendingKind = ""
    private var pendingBytes: ByteArray? = null
    private var pendingRevision = 0L
    private var revision: Long
        get() = sessions.active.revision
        set(value) { sessions.active.revision=value }
    private var recoveryError: String?
        get() = sessions.active.recoveryError
        set(value) { sessions.active.recoveryError=value }
    private var pendingDocument = 0
    private val externalUris = java.util.concurrent.ConcurrentLinkedQueue<Uri>()
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
        val permissions=value.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try { contentResolver.takePersistableUriPermission(uri, permissions) } catch(_: SecurityException) { }
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
            val opened=sessions.add(loaded, uri.lastPathSegment?.substringAfterLast('/') ?: "Opened document")
            // VIEW commonly grants read-only access. Saving always asks for a destination.
            opened.path=null
            revision++
        } catch(e: Exception) { externalOpenError="Could not open project: ${e.message}" }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        externalChannel=MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pocketpixel/external")
        enqueueExternal(intent)
        val files=recoveryFiles()
        files.forEach { f -> Regex("recovery-([0-9]+)\\.aseprite").matchEntire(f.name)?.groupValues?.get(1)?.toIntOrNull()?.let { sessions.nextId=maxOf(sessions.nextId,it+1) } }
        if(files.isNotEmpty()) {sessions.documents.clear();val blank=EditorSession(sessions.nextId++);sessions.configure(blank);sessions.documents.add(blank);sessions.activeId=blank.id;startupRecovery=true}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pocketpixel/editor").setMethodCallHandler(::handle)
    }
    private fun recoveryFiles() = recoveryBaseFiles(filesDir)
    private fun state() = sessions.state(startupRecovery || recovery.baseFile.exists() || File(recovery.baseFile.path+".bak").exists()) + mapOf("externalPending" to externalUris.isNotEmpty(), "externalOpenError" to (externalQueueError ?: externalOpenError))
    private fun recoverDocuments() {
        val files=recoveryFiles()
        val existing=sessions.documents.map { it.id }.toSet()
        fun id(f: File)=Regex("recovery-([0-9]+)\\.aseprite").matchEntire(f.name)?.groupValues?.get(1)?.toIntOrNull()
        val needed=files.count { id(it) !in existing }
        val placeholder=if(sessions.documents.size==1 && sessions.active.placeholder && !editor.dirty)1 else 0
        require(sessions.documents.size+needed-placeholder<=8) { "Close documents before recovering more (8 maximum)." }
        require(files.sumOf { maxOf(it.length(),File(it.path+".bak").length()) }<=Aseprite.MAX_FILE) { "Combined recovery exceeds the 64 MiB safety budget. Original recovery files were retained." }
        var decodedPixels=0L
        val decoded=files.map { f ->
            // AtomicFile promotes a valid legacy backup before reading; reading
            // the base directly could decode a partially replaced file.
            val doc=Aseprite.read(AtomicFile(f).readFully())
            decodedPixels+=doc.frames.sumOf { frame -> frame.cels.sumOf { it?.pixels?.size?.toLong() ?: 0L } }
            require(decodedPixels<=16L*1024*1024) { "Combined recovery exceeds the decoded-pixel budget. Original recovery files were retained." }
            f to doc
        }
        sessions.validateRecoveryCandidates(decoded.map {it.second},files.mapNotNull(::id).toSet())
        val restored=sessions.restoreDecoded(decoded.map {(file,doc)->id(file) to doc})
        val selectedAfterRestore=sessions.activeId
        restored.forEachIndexed { index,session ->
            sessions.select(session.id);changed()
            val file=files[index]
            if(recoveryError==null && file.absolutePath!=recovery.baseFile.absolutePath)AtomicFile(file).delete()
        }
        sessions.select(selectedAfterRestore)
        startupRecovery=false
    }
    private fun execute(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try { val value=block(); if(value !== DeferredResult) main.post { result.success(value) } }
            catch(e: Exception) { main.post { result.error("editor_error", e.message ?: e.javaClass.simpleName, null) } }
        }
    }
    private fun persist() {
        val bytes=Aseprite.write(editor.document)
        val stream=recovery.startWrite()
        try { stream.write(bytes); recovery.finishWrite(stream); recoveryError=null }
        catch(e: Exception) { recovery.failWrite(stream); throw e }
    }
    private fun changed() {
        revision++
        // Keep edits in memory if storage fills; make recovery failure visible in state.
        try { persist() } catch(e: Exception) { recoveryError="Recovery could not be written: ${e.message}. Save a copy now." }
    }
    @Suppress("UNCHECKED_CAST")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args=call.arguments as? Map<String, Any?> ?: emptyMap()
        if (call.method in listOf("open","saveAs","exportPng")) { launchPicker(call.method,result); return }
        execute(result) {
            when(call.method) {
                "init", "state" -> Unit
                "openExternal" -> openExternal()
                "thumbnails" -> return@execute editor.thumbnails(args)
                "new" -> { sessions.add(Document.create(args.number("width",32),args.number("height",32)),unsaved=true); changed() }
                "selectDocument" -> sessions.select(args.number("id",-1))
                "closeDocument" -> {val id=args.number("id",-1);sessions.close(id,args["discard"]==true);AtomicFile(File(filesDir,"recovery-$id.aseprite")).delete()}
                "clearTagClipboard" -> sessions.clearClipboard()
                "copyTag" -> sessions.copyTag(args.number("index",-1))
                "pasteTag" -> {if(args["asNew"]==true)sessions.pasteTagAsNew() else sessions.pasteTag((args["after"] as? Number)?.toInt());changed()}
                "select" -> editor.select(args)
                "stroke" -> { editor.stroke(args); changed() }
                "edit" -> { editor.edit(args); changed() }
                "undo" -> { editor.undo(); changed() }
                "redo" -> { editor.redo(); changed() }
                "recover" -> recoverDocuments()
                "discardRecovery" -> {
                    val protectedNames=sessions.documents.filter {it.id!=sessions.activeId}.map {"recovery-${it.id}.aseprite"}.toSet()
                    recoveryFiles().filter {it.name !in protectedNames}.forEach {AtomicFile(it).delete()}
                    startupRecovery=false;recoveryError=null
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
    private fun writeDocument(uri: Uri) {
        val bytes=Aseprite.write(editor.document)
        Aseprite.read(bytes) // Validate before opening any destination for truncation.
        persist()
        contentResolver.openOutputStream(uri,"wt")?.use { it.write(bytes); it.flush() } ?: error("The document provider refused this file. Use Save As.")
        editor.saved(); currentUri=uri; sessions.active.title=uri.lastPathSegment?.substringAfterLast('/') ?: sessions.active.title; recovery.delete(); recoveryError=null
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
                        while(true) { val n=stream.read(buffer); if(n<0) break; require(out.size()+n<=128*1024*1024) { "File exceeds the 128 MiB safety limit" }; out.write(buffer,0,n) }
                        Aseprite.read(out.toByteArray())
                    } ?: error("The document provider could not read this file")
                    val opened=sessions.add(loaded, uri.lastPathSegment?.substringAfterLast('/') ?: "Opened document")
                    opened.path=uri.toString();revision++
                } else {
                    requireNotNull(bytes)
                    contentResolver.openOutputStream(uri,"wt")?.use { it.write(bytes); it.flush() } ?: error("The document provider refused this file")
                    if(kind=="saveAs") { currentUri=uri;sessions.active.title=uri.lastPathSegment?.substringAfterLast('/') ?: sessions.active.title; if(revision==snapshotRevision) { editor.saved(); recovery.delete(); recoveryError=null } }
                }
            }
            state()
        }
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
