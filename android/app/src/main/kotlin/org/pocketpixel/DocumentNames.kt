package org.pocketpixel

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns

/** Presentation metadata only. Never use a provider's name as a filesystem path.
 * Call on the editor worker: even a small metadata query can block on a provider. */
internal class DocumentNames(private val resolver: ContentResolver) {
    fun resolve(uri: Uri, fallback: String = "Opened document"): String =
        providerName(uri) ?: if (uri.scheme == "file") {
            usable(uri.lastPathSegment) ?: fallback
        } else fallback

    private fun usable(value: String?): String? = value?.takeIf { it.isNotBlank() }?.take(512)

    private fun providerName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        return try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column < 0 || !cursor.moveToFirst() || cursor.isNull(column)) null
                else usable(cursor.getString(column))
            }
        } catch (_: Exception) {
            // Missing/revoked grants and broken or offline providers must not
            // turn a successful project read/write into a failure.
            null
        }
    }

    /** Old drafts used the decoded URI tail as their title. Only replace that
     * exact legacy value, never an independently named document. Null means the
     * provider is unavailable, so retain the label and retry on a later reopen.
     * This queries existing access only; it never acquires or restores a grant. */
    fun refreshLegacy(sourceUri: String?, title: String): String? {
        val uri = sourceUri?.let(Uri::parse) ?: return title
        if (uri.scheme != "content" || title != uri.lastPathSegment?.substringAfterLast('/')?.take(512)) return title
        return providerName(uri)
    }
}
