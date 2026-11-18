package org.pocketpixel

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document.COLUMN_FLAGS
import android.provider.DocumentsContract.Document.FLAG_SUPPORTS_WRITE
import java.io.DataInputStream
import java.io.EOFException
import java.io.FileNotFoundException
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Project I/O belongs on the editor worker. A display name is never a write target. */
internal class ProjectFiles(private val context: Context) {
    private val resolver get() = context.contentResolver

    fun read(uri: Uri): Document = resolver.openInputStream(uri)?.use { input ->
        val stream = DataInputStream(input)
        val header = ByteArray(6)
        try {
            stream.readFully(header)
            val fields = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            val size = fields.int
            require(fields.short.toInt() and 0xffff == 0xA5E0) { "Not an Aseprite project" }
            require(size in 128..Aseprite.MAX_FILE) { "Invalid project size or file exceeds 64 MiB" }
            val bytes = header.copyOf(size)
            stream.readFully(bytes, header.size, size - header.size)
            require(stream.read() == -1) { "Unexpected data after the Aseprite project" }
            Aseprite.read(bytes)
        } catch (_: EOFException) {
            throw AsepriteException("Incomplete Aseprite project")
        }
    } ?: error("The provider could not read this project")

    fun writableTarget(uri: Uri, flags: Int): Uri? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT || flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION == 0) return null
        // FileProvider does not implement DocumentsContract. Its URI grant is sufficient.
        if (DocumentsContract.isDocumentUri(context, uri)) {
            val supported = try {
                resolver.query(uri, arrayOf(COLUMN_FLAGS), null, null, null)?.use { cursor ->
                    val column = cursor.getColumnIndex(COLUMN_FLAGS)
                    if (column < 0 || !cursor.moveToFirst() || cursor.isNull(column)) null
                    else cursor.getInt(column) and FLAG_SUPPORTS_WRITE != 0
                }
            } catch (_: SecurityException) {
                false
            } catch (_: RuntimeException) {
                null // Some providers omit this optional metadata.
            }
            if (supported == false) return null
        }
        return uri
    }

    fun openOutput(uri: Uri): OutputStream {
        require(uri.scheme == ContentResolver.SCHEME_CONTENT) { "Choose a document provider to save this file" }
        // Some providers accept only the standard "w" mode. Its truncation
        // behavior is provider-defined, so truncate regular files ourselves there.
        val output = try {
            resolver.openOutputStream(uri, "wt")
        } catch (_: FileNotFoundException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        } catch (_: UnsupportedOperationException) {
            null
        }
        if (output != null) return output
        val descriptor = resolver.openFileDescriptor(uri, "w") ?: throw FileNotFoundException("The provider could not open the destination")
        val stream = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
        try {
            if (descriptor.statSize >= 0) stream.channel.truncate(0)
            return stream
        } catch (e: Exception) {
            stream.close()
            throw e
        }
    }

    fun outputForExisting(uri: Uri): OutputStream? = try {
        openOutput(uri)
    } catch (_: SecurityException) {
        null // The grant expired. Save As can still write the in-memory project.
    } catch (_: FileNotFoundException) {
        null // The file was removed or the provider no longer permits updates.
    }

    companion object {
        const val MIME_TYPE = "image/x-aseprite"

        fun suggestedName(title: String): String {
            val name = title.replace(Regex("""[/\\\p{Cntrl}]"""), "_").trim().ifEmpty { "sprite" }
            return if (name.endsWith(".aseprite", true) || name.endsWith(".ase", true)) name else "$name.aseprite"
        }
    }
}
