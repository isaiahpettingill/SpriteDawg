package org.pocketpixel

import android.content.Intent
import android.graphics.Bitmap
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
    private val editor = EditorEngine()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var recovery: AtomicFile
    private var currentUri: Uri? = null
    private var pending: MethodChannel.Result? = null
    private var pendingKind = ""
    private var pendingBytes: ByteArray? = null
    private var pendingRevision = 0L
    private var revision = 0L
    private var recoveryError: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        recovery = AtomicFile(File(filesDir,"recovery.aseprite"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"pocketpixel/editor").setMethodCallHandler(::handle)
    }
    private fun state() = editor.state(recovery.baseFile.exists()).toMutableMap().also {
        it["recoveryError"] = recoveryError
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
                "new" -> { editor.replace(Document.create(args.number("width",32),args.number("height",32)),true); currentUri=null; changed() }
                "select" -> editor.select(args)
                "stroke" -> { editor.stroke(args); changed() }
                "edit" -> { editor.edit(args); changed() }
                "undo" -> { editor.undo(); changed() }
                "redo" -> { editor.redo(); changed() }
                "recover" -> { val doc=Aseprite.read(recovery.readFully()); editor.replace(doc,true); currentUri=null; revision++ }
                "discardRecovery" -> { recovery.delete(); recoveryError=null }
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
        editor.saved(); currentUri=uri; recovery.delete(); recoveryError=null
    }
    private fun launchPicker(kind: String,result: MethodChannel.Result) {
        if(pending!=null) { result.error("busy","Finish the open file picker first",null); return }
        pending=result; pendingKind=kind
        if(kind=="open") {
            val intent=Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="*/*"; addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }
            try { startActivityForResult(intent,42) } catch(e: Exception) { pending=null; result.error("picker_error",e.message,null) }
        } else {
            worker.execute {
                try {
                    pendingBytes=if(kind=="exportPng") {
                        val d=editor.document; val bitmap=Bitmap.createBitmap(d.composite(editor.frame),d.width,d.height,Bitmap.Config.ARGB_8888)
                        java.io.ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG,100,out); bitmap.recycle(); out.toByteArray() }
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
        val kind=pendingKind; val bytes=pendingBytes; val snapshotRevision=pendingRevision
        pending=null; pendingBytes=null
        execute(result) {
            val uri=data?.data
            if(resultCode==RESULT_OK && uri!=null) {
                try { contentResolver.takePersistableUriPermission(uri,((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))) } catch(_: SecurityException) { /* A provider may offer only this session. */ }
                if(kind=="open") {
                    val loaded=contentResolver.openInputStream(uri)?.use { stream ->
                        val out=java.io.ByteArrayOutputStream(); val buffer=ByteArray(65536)
                        while(true) { val n=stream.read(buffer); if(n<0) break; require(out.size()+n<=128*1024*1024) { "File exceeds the 128 MiB safety limit" }; out.write(buffer,0,n) }
                        Aseprite.read(out.toByteArray())
                    } ?: error("The document provider could not read this file")
                    editor.replace(loaded); currentUri=uri; revision++; recovery.delete(); recoveryError=null
                } else {
                    requireNotNull(bytes)
                    contentResolver.openOutputStream(uri,"wt")?.use { it.write(bytes); it.flush() } ?: error("The document provider refused this file")
                    if(kind=="saveAs") { currentUri=uri; if(revision==snapshotRevision) { editor.saved(); recovery.delete(); recoveryError=null } }
                }
            }
            state()
        }
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
