package org.pocketpixel

import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.OpenableColumns
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class DocumentNamesTest {
    private val uri = Uri.parse("content://com.android.providers.downloads.documents/document/1936")
    private lateinit var provider: NamesProvider
    private lateinit var names: DocumentNames

    @Before fun setup() {
        provider = Robolectric.buildContentProvider(NamesProvider::class.java)
            .create(ProviderInfo().apply { authority = uri.authority })
            .get()
        names = DocumentNames(RuntimeEnvironment.getApplication().contentResolver)
    }

    @Test fun numericAndOpaqueDocumentIdsUseProviderNamesIncludingUnicodeAndExtensions() {
        for (id in listOf("1936", "msf%3A1936", "c10f84c0-764e-4b24-97d7-ffe9877b0b23")) {
            for (title in listOf("Forest.aseprite", "树叶 🌿 été.ASE", "no extension", "1936")) {
                val cursor = MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOf(title)) }
                provider.answer = { cursor }
                assertEquals(title, names.resolve(Uri.parse("content://${uri.authority}/document/$id")))
                assertTrue(cursor.isClosed)
                assertArrayEquals(arrayOf(OpenableColumns.DISPLAY_NAME), provider.projection)
            }
        }
    }

    @Test fun absentNullBlankOrEmptyMetadataFallsBackWithoutLeakingIds() {
        val cursors = listOf(
            null,
            MatrixCursor(arrayOf("unexpected")).apply { addRow(arrayOf("not a name")) },
            MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)),
            MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOfNulls<String>(1)) },
            MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOf("  ")) },
        )
        cursors.forEach { cursor ->
            provider.answer = { cursor }
            assertEquals("Opened document", names.resolve(uri))
            assertTrue(cursor == null || cursor.isClosed)
        }
        provider.answer = { null }
        assertEquals("My known name.aseprite", names.resolve(uri, "My known name.aseprite"))
    }

    @Test fun revokedPermissionsAndProviderFailuresDoNotBlockOpenOrSave() {
        listOf(SecurityException("revoked"), IllegalArgumentException("unsupported query"), IllegalStateException("offline")).forEach { error ->
            provider.answer = { throw error }
            assertEquals("Opened document", names.resolve(uri))
            assertEquals("Saved name.aseprite", names.resolve(uri, "Saved name.aseprite"))
            assertNull(names.refreshLegacy(uri.toString(), "1936"))
        }
    }

    @Test fun cursorIsClosedWhenReadingMetadataFails() {
        val cursor = object : MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)) {
            override fun getString(column: Int): String = throw IllegalStateException("bad provider value")
        }.apply { addRow(arrayOf("ignored")) }
        provider.answer = { cursor }
        assertEquals("Opened document", names.resolve(uri))
        assertTrue(cursor.isClosed)
    }

    @Test fun fileUriUsesDecodedBasenameWithoutQueryingProvider() {
        provider.answer = { error("file names must not query a provider") }
        assertEquals("树叶 sprite.aseprite", names.resolve(Uri.parse("file:///storage/emulated/0/Art/%E6%A0%91%E5%8F%B6%20sprite.aseprite")))
    }

    @Test fun onlyExactLegacyUriTitlesAreRefreshedAndNamesAreNotInterpretedAsPaths() {
        provider.answer = { MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOf("../Tree 🌳.aseprite")) } }
        assertEquals("../Tree 🌳.aseprite", names.refreshLegacy(uri.toString(), "1936"))
        assertEquals("../Tree 🌳.aseprite", names.resolve(uri))
        provider.answer = { error("must preserve independently chosen titles") }
        assertEquals("My forest", names.refreshLegacy(uri.toString(), "My forest"))
        assertEquals("1936", names.refreshLegacy(null, "1936"))
        assertEquals("1936", names.refreshLegacy("file:///Art/1936", "1936"))
    }

    class NamesProvider : ContentProvider() {
        var answer: () -> Cursor? = { null }
        var projection: Array<out String>? = null
        override fun onCreate() = true
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
            this.projection = projection
            return answer()
        }
        override fun getType(uri: Uri) = "application/octet-stream"
        override fun insert(uri: Uri, values: ContentValues?): Uri? = error("not used")
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = error("not used")
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = error("not used")
    }
}
