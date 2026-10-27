package org.pocketpixel

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/** SAF export destinations; a paired sheet always gets its own new folder. */
class ExportFiles(private val activity: Activity, private val worker: Executor, private val main: Handler) {
    companion object { const val REQUEST = 43 }
    private var pending: MethodChannel.Result? = null
    private var files = emptyMap<String, ByteArray>()
    private var name = "sprite"
    val busy get() = pending != null

    fun begin(args: Map<String, Any?>, result: MethodChannel.Result) {
        if (busy) { result.error("busy", "Finish the export picker first", null); return }
        try {
            name = args["name"] as? String ?: error("Missing export name")
            require(Regex("^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$").matches(name)) { "Invalid export name" }
            val raw = args["files"] as? Map<*, *> ?: error("Missing export files")
            require(raw.size in 1..2) { "Invalid export file count" }
            files = raw.entries.associate { entry ->
                val filename = entry.key as? String ?: error("Invalid export filename")
                require(Regex("^[A-Za-z0-9][A-Za-z0-9 _.-]{0,80}$").matches(filename)) { "Invalid export filename" }
                filename to (entry.value as? ByteArray ?: error("Invalid export bytes"))
            }
            require(files.values.sumOf { it.size.toLong() } <= 128 * 1024 * 1024) { "Export exceeds 128 MiB" }
            pending = result
            val intent = if (files.size == 2) {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            } else {
                val filename = files.keys.single()
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime(filename)
                    putExtra(Intent.EXTRA_TITLE, filename)
                }
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: Exception) {
            pending = null; files = emptyMap()
            result.error("export_error", e.message, null)
        }
    }

    fun complete(resultCode: Int, data: Intent?) {
        val result = pending ?: return
        // Retain busy ownership until the worker finishes; no second picker can
        // replace these immutable byte buffers during a slow provider write.
        val snapshot = files
        val baseName = name
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null; files = emptyMap(); result.success(mapOf("saved" to false)); return
        }
        worker.execute {
            var createdFolder: Uri? = null
            try {
                if (snapshot.size == 1) {
                    write(uri, snapshot.values.single())
                } else {
                    val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
                    val folder = DocumentsContract.createDocument(activity.contentResolver, root,
                        DocumentsContract.Document.MIME_TYPE_DIR, "$baseName-spritesheet")
                        ?: error("The provider could not create an export folder")
                    createdFolder = folder
                    for ((filename, bytes) in snapshot) {
                        val child = DocumentsContract.createDocument(activity.contentResolver, folder, mime(filename), filename)
                            ?: error("The provider could not create $filename")
                        val actualName = activity.contentResolver.query(child,
                            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                            if (it.moveToFirst()) it.getString(0) else null
                        }
                        require(actualName == filename) { "The provider renamed $filename; JSON pairing would be incorrect" }
                        write(child, bytes)
                    }
                }
                main.post {
                    pending = null; files = emptyMap()
                    result.success(mapOf("saved" to true, "location" to createdFolder?.toString()))
                }
            } catch (e: Exception) {
                var remainder = false
                // ACTION_CREATE_DOCUMENT returns a newly created destination,
                // never the currently opened source project. Remove partial
                // output if the provider supports deletion; report leftovers.
                val incomplete = createdFolder ?: if (snapshot.size == 1) uri else null
                if (incomplete != null) {
                    remainder = try { !DocumentsContract.deleteDocument(activity.contentResolver, incomplete) } catch (_: Exception) { true }
                }
                val suffix = if (remainder) ". An incomplete export remains; remove it before retrying." else ""
                main.post {
                    pending = null; files = emptyMap()
                    result.error("export_error", (e.message ?: "Export failed") + suffix, null)
                }
            }
        }
    }

    private fun write(uri: Uri, bytes: ByteArray) {
        activity.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
            ?: error("The provider refused the export file")
    }
    private fun mime(name: String): String = when (name.substringAfterLast('.')) {
        "png", "apng" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "avif" -> "image/avif"
        "json" -> "application/json"
        else -> "application/octet-stream"
    }
}
