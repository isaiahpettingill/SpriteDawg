package org.pocketpixel

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.io.FileNotFoundException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class ProjectFilesTest {
    private val uri = Uri.parse("content://test.projects/document/1936")
    private lateinit var provider: ProjectProvider
    private lateinit var files: ProjectFiles

    @Before fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        provider = Robolectric.buildContentProvider(ProjectProvider::class.java)
            .create(ProviderInfo().apply { authority = uri.authority }).get()
        provider.file = File(context.cacheDir, "opaque-project")
        files = ProjectFiles(context)
    }

    @Test fun writableAndReadOnlyGrantsSelectDifferentSaveTargets() {
        assertNull(files.writableTarget(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION))
        assertEquals(uri, files.writableTarget(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
        assertNull(files.writableTarget(Uri.fromFile(provider.file), Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
    }

    @Test fun savesOnStandardAndWriteOnlyProvidersTruncateAndReopen() {
        val document = Document.create(3, 2).also { it.data = UserData(text = "saved metadata") }
        val bytes = Aseprite.write(document)
        for (standardOnly in listOf(false, true)) {
            provider.standardOnly = standardOnly
            provider.file.writeBytes(ByteArray(bytes.size + 200))
            checkNotNull(files.outputForExisting(uri)).use { it.write(bytes) }
            assertArrayEquals(bytes, provider.file.readBytes())
            val opened = files.read(uri)
            assertEquals(3, opened.width)
            assertEquals("saved metadata", opened.data?.text)
        }
    }

    @Test fun revokedOrMissingTargetCanSwitchToSaveAs() {
        provider.file.writeText("original")
        provider.writeFailure = SecurityException("revoked")
        assertNull(files.outputForExisting(uri))
        provider.writeFailure = FileNotFoundException("removed")
        assertNull(files.outputForExisting(uri))
        assertEquals("original", provider.file.readText())
    }

    @Test fun invalidBinaryAndTruncatedProjectsAreRejected() {
        val bytes = Aseprite.write(Document.create(1, 1))
        for (bad in listOf(ByteArray(128), bytes.copyOf(5), bytes.copyOf(bytes.size - 1), bytes + 1.toByte())) {
            provider.file.writeBytes(bad)
            assertThrows(IllegalArgumentException::class.java) { files.read(uri) }
        }
    }

    @Test fun saveAsPreservesTheProjectNameAndExtension() {
        assertEquals("Tree 🌳.v3.ASE", ProjectFiles.suggestedName("Tree 🌳.v3.ASE"))
        assertEquals("walk.aseprite", ProjectFiles.suggestedName("walk"))
        assertEquals("art_walk.aseprite", ProjectFiles.suggestedName("art/walk.aseprite"))
    }

    class ProjectProvider : ContentProvider() {
        lateinit var file: File
        var standardOnly = false
        var writeFailure: Exception? = null
        override fun onCreate() = true
        override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
            if (mode != "r") writeFailure?.let { throw it }
            val flags = when (mode) {
                "r" -> ParcelFileDescriptor.MODE_READ_ONLY
                "wt" -> if (standardOnly) throw FileNotFoundException("Unsupported mode")
                    else ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_TRUNCATE
                "w" -> ParcelFileDescriptor.MODE_WRITE_ONLY // Intentionally retains trailing bytes.
                else -> error("Unexpected mode $mode")
            }
            return ParcelFileDescriptor.open(file, flags)
        }
        override fun getType(uri: Uri) = "application/octet-stream"
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = error("unused")
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = error("unused")
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = error("unused")
    }
}
