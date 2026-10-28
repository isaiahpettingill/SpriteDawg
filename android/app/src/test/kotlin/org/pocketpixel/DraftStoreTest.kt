package org.pocketpixel

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class DraftStoreTest {
    private fun directory(test: (File) -> Unit) {
        val dir = Files.createTempDirectory("spritedawg-drafts-").toFile()
        try { test(dir) } finally { dir.deleteRecursively() }
    }
    private fun drawing(label: String) = Document.create(2, 2).also { it.data = UserData(text = label) }

    private fun oldDraft(dir: File, title: String = "1936") {
        val body = java.io.ByteArrayOutputStream()
        java.io.DataOutputStream(body).use { out ->
            out.writeInt(0x53444431); out.writeInt(2); out.writeLong(1234L)
            out.writeUTF(title); out.writeUTF("content://downloads/document/1936")
            val bytes = Aseprite.write(drawing("legacy artwork"))
            out.writeInt(bytes.size); out.write(bytes)
        }
        val payload = body.toByteArray()
        java.io.DataOutputStream(dir.resolve("draft-2.sdd").outputStream()).use { out ->
            out.writeLong(java.util.zip.CRC32().apply { update(payload) }.value)
            out.write(payload)
        }
    }

    @Test fun legacyNameIsRefreshedInPickerAndRecoveryThenPersistedAcrossLostAccess() = directory { dir ->
        oldDraft(dir)
        val store = DraftStore(dir, resolveLegacyTitle = { source, title ->
            assertEquals("content://downloads/document/1936", source)
            assertEquals("1936", title)
            "树叶 🌿.aseprite"
        })
        assertEquals("树叶 🌿.aseprite", store.summaries().single()["title"])
        val recovered = store.read(2)
        assertTrue(recovered.titleRefreshed)
        assertFalse(recovered.titleNeedsRefresh)
        assertEquals("legacy artwork", recovered.document.data!!.text)
        assertEquals(1234L, recovered.updatedAt)
        store.write(2, recovered.title, recovered.sourceUri, recovered.document, recovered.updatedAt, recovered.titleNeedsRefresh)
        val restarted = DraftStore(dir, resolveLegacyTitle = { _, _ -> error("confirmed titles must not query") })
        assertEquals("树叶 🌿.aseprite", restarted.summaries().single()["title"])
        assertFalse(restarted.read(2).titleNeedsRefresh)
        assertEquals("legacy artwork", restarted.read(2).document.data!!.text)
    }

    @Test fun unavailableLegacyNameRetainsArtworkAndRetriesAfterAnotherSnapshot() = directory { dir ->
        oldDraft(dir)
        val unavailable = DraftStore(dir, resolveLegacyTitle = { _, _ -> throw SecurityException("revoked") })
        val recovered = unavailable.read(2)
        assertEquals("1936", recovered.title)
        assertTrue(recovered.titleNeedsRefresh)
        assertFalse(recovered.titleRefreshed)
        unavailable.write(2, recovered.title, recovered.sourceUri, recovered.document, titleNeedsRefresh = recovered.titleNeedsRefresh)
        val accessible = DraftStore(dir, resolveLegacyTitle = { _, _ -> "Forest.aseprite" })
        assertEquals("Forest.aseprite", accessible.read(2).title)
        assertEquals("legacy artwork", accessible.read(2).document.data!!.text)
    }

    @Test fun newNamesIncludingNumericNamesAreNeverMistakenForLegacyIds() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "1936", "content://downloads/document/1936", drawing("explicit numeric name"))
        val restarted = DraftStore(dir, resolveLegacyTitle = { _, _ -> error("new names are authoritative") })
        assertEquals("1936", restarted.read(2).title)
        assertFalse(restarted.read(2).titleNeedsRefresh)
    }

    @Test fun restartKeepsIndependentNamedDraftsAndSourceMetadata() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "Untitled", null, drawing("new"), 10)
        store.write(3, "Imported.aseprite", "content://example/document/source", drawing("imported"), 20)
        val restarted = DraftStore(dir)
        assertEquals(listOf(3, 2), restarted.summaries().map { it["id"] })
        assertEquals("new", restarted.read(2).document.data!!.text)
        val imported = restarted.read(3)
        assertEquals("Imported.aseprite", imported.title)
        assertEquals("content://example/document/source", imported.sourceUri)
        assertEquals(20L, imported.updatedAt)
        val sessions = EditorSessions()
        sessions.nextId = 4
        val restored = sessions.restoreDecoded(listOf(3 to imported.document)).single()
        assertEquals(3, restored.id)
        assertNull(restored.path)
        assertTrue(restored.engine.dirty)
        assertTrue(sessions.nextId > restored.id)
    }

    @Test fun corruptLatestUsesLastGoodAndDoesNotBlockAnotherDraft() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "First", null, drawing("previous"), 10)
        store.write(2, "First", null, drawing("latest"), 20)
        store.write(3, "Second", null, drawing("healthy"), 30)
        dir.resolve("draft-2.sdd").writeText("interrupted/corrupt latest")
        val restarted = DraftStore(dir)
        assertTrue(restarted.read(2).fallback)
        assertEquals("previous", restarted.read(2).document.data!!.text)
        assertEquals("healthy", restarted.read(3).document.data!!.text)
        assertEquals(2, restarted.summaries().size)
        // A later successful snapshot must not rotate the damaged latest over
        // the sole remaining valid previous generation.
        restarted.write(2, "First", null, drawing("repaired"), 40)
        dir.resolve("draft-2.sdd").writeText("corrupt again")
        assertEquals("previous", DraftStore(dir).read(2).document.data!!.text)
    }

    @Test fun unreadableDraftRemainsVisibleAndCanBeExplicitlyDeleted() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "Broken", null, drawing("only copy"))
        store.write(3, "Healthy", null, drawing("healthy"))
        dir.resolve("draft-2.sdd").writeBytes(byteArrayOf(1, 2, 3))
        val restarted = DraftStore(dir)
        assertNotNull(restarted.summaries().first { it["id"] == 2 }["error"])
        assertEquals("healthy", restarted.read(3).document.data!!.text)
        restarted.delete(2)
        assertEquals(listOf(3), DraftStore(dir).summaries().map { it["id"] })
    }

    @Test fun quotaAndCountFailuresNeverEvictExistingWork() = directory { dir ->
        val one = DraftStore(dir, maximumDrafts = 1)
        one.write(2, "Retain", null, drawing("retain"))
        try { one.write(3, "Refused", null, drawing("refused")); fail("must enforce count") }
        catch (_: IllegalArgumentException) { }
        val before = dir.resolve("draft-2.sdd").readBytes()
        val noSpace = DraftStore(dir, capacity = 1)
        try { noSpace.write(2, "Changed", null, drawing("changed")); fail("must enforce capacity") }
        catch (_: IllegalArgumentException) { }
        assertArrayEquals(before, dir.resolve("draft-2.sdd").readBytes())
        assertEquals("retain", DraftStore(dir).read(2).document.data!!.text)
        assertEquals(listOf(2), DraftStore(dir).summaries().map { it["id"] })
    }

    @Test fun failedAtomicWriteLeavesLastCommittedSnapshotReadable() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "Keep", null, drawing("committed"))
        // A filesystem failure after previous-generation rotation but before
        // current publication must retain the original current generation.
        dir.resolve("draft-2.sdd.tmp").mkdir()
        try { store.write(2, "Keep", null, drawing("not committed")); fail("must fail write") }
        catch (_: java.io.IOException) { }
        assertEquals("committed", DraftStore(dir).read(2).document.data!!.text)
    }

    @Test fun legacyBackupAndUnnumberedRecoveryArePreserved() = directory { dir ->
        dir.resolve("recovery-8.aseprite.bak").writeBytes(Aseprite.write(drawing("backup")))
        dir.resolve("recovery.aseprite").writeBytes(Aseprite.write(drawing("legacy")))
        dir.resolve("recovery-9.aseprite.new").writeBytes(Aseprite.write(drawing("uncommitted")))
        val store = DraftStore(dir)
        assertEquals(setOf(0, 8), store.summaries().map { it["id"] }.toSet())
        assertEquals("backup", store.read(8).document.data!!.text)
        assertEquals("legacy", store.read(0).document.data!!.text)
        store.write(8, "Migrated", null, store.read(8).document)
        assertFalse(dir.resolve("recovery-8.aseprite.bak").exists())
        assertTrue(dir.resolve("recovery.aseprite").exists())
    }

    @Test fun checksumIncludesMetadataAndInterruptedTemporaryIsNotRecovered() = directory { dir ->
        val store = DraftStore(dir)
        store.write(2, "First", null, drawing("first"))
        val bytes = dir.resolve("draft-2.sdd").readBytes()
        bytes[20] = (bytes[20].toInt() xor 1).toByte()
        dir.resolve("draft-2.sdd").writeBytes(bytes)
        dir.resolve("draft-3.sdd.tmp").writeBytes(bytes)
        val summaries = DraftStore(dir).summaries()
        assertEquals(1, summaries.size)
        assertNotNull(summaries.single()["error"])
    }

    @Test fun pendingIdsCoalesceAndFlushLatestOfEachDocument() {
        val pending = DraftPending()
        val latest = mutableMapOf(2 to "first", 3 to "second")
        pending.mark(2, 100)
        repeat(20) { pending.mark(2, 200L + it) }
        pending.mark(3, 250)
        latest[2] = "newest"
        val written = mutableMapOf<Int, String>()
        pending.flush { id -> written[id] = latest.getValue(id); true }
        assertEquals(mapOf(2 to "newest", 3 to "second"), written)
        assertFalse(pending.contains(2))
        assertFalse(pending.contains(3))
    }

    @Test fun discardAndSaveCancelPendingWritesAndFailuresRemainRetryable() {
        val pending = DraftPending()
        pending.mark(2, 100); pending.mark(3, 200); pending.mark(4, 250)
        pending.forget(2) // explicit discard/close
        pending.forget(3) // manual save succeeded
        val writes = mutableListOf<Int>()
        pending.flush { id -> writes.add(id); false }
        assertEquals(listOf(4), writes)
        assertTrue(pending.contains(4))
        pending.flush { id -> writes.add(id); true }
        assertEquals(listOf(4, 4), writes)
        assertFalse(pending.contains(4))
    }

    @Test fun continuousEditingHasBoundedAutosaveDelay() {
        val pending = DraftPending()
        pending.mark(2, 1000)
        assertEquals(600L, pending.delay(1000))
        pending.mark(2, 2800)
        assertEquals(200L, pending.delay(2800))
        assertEquals(0L, pending.delay(3000))
        pending.flush { true }
        pending.mark(3, 5000)
        assertEquals(600L, pending.delay(5000))
    }
    @Test fun failedFlushStartsFreshDebounceWindowForContinuedEditing() {
        val pending = DraftPending()
        pending.mark(2, 100)
        assertEquals(0L, pending.delay(2100))
        pending.flush { false }
        assertTrue(pending.contains(2))
        pending.mark(2, 3000)
        assertEquals(600L, pending.delay(3000))
        pending.mark(3, 4500)
        assertEquals(500L, pending.delay(4500))
        pending.flush { false }
        pending.mark(2, 7000)
        assertEquals(600L, pending.delay(7000))
        assertTrue(pending.contains(3))
    }

}
