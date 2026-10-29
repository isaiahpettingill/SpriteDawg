package org.pocketpixel

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class WorkspaceRestoreTest {
    private fun withStorage(test: (java.io.File, MutableList<NativeEditorRuntime>) -> Unit) {
        val dir = Files.createTempDirectory("workspace-test").toFile()
        val runtimes = mutableListOf<NativeEditorRuntime>()
        try { test(dir, runtimes) }
        finally { runtimes.forEach { it.worker.shutdownNow() }; dir.deleteRecursively() }
    }
    private fun runtime(dir: java.io.File, runtimes: MutableList<NativeEditorRuntime>) =
        NativeEditorRuntime().also { runtimes.add(it); it.initialize(dir) }
    private fun snapshot(runtime: NativeEditorRuntime) {
        runtime.sessions.documents.forEach { s ->
            runtime.drafts.write(s.id, s.title, s.sourceUri, s.engine.document)
        }
        runtime.saveWorkspace()
        assertNull(runtime.workspaceError)
    }
    @Test fun firstLaunchIsEmptyAndDimensionsPersistEvenWhenLastTabClosed() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        assertTrue(first.sessions.documents.isEmpty())
        assertEquals(false, first.sessions.state(false)["hasDocument"])
        assertEquals(0, first.sessions.state(false)["width"])
        assertThrows(IllegalStateException::class.java) { first.sessions.active }
        first.sessions.add(Document.create(16, 24), unsaved = true)
        first.lastNewWidth = 16; first.lastNewHeight = 24
        snapshot(first)
        first.sessions.close(first.sessions.activeId, true)
        first.saveWorkspace() // Keep the old draft, but explicitly close its tab.
        val second = runtime(dir, runtimes)
        assertTrue(second.sessions.documents.isEmpty())
        assertEquals(16, second.lastNewWidth); assertEquals(24, second.lastNewHeight)
        assertEquals(1, second.drafts.summaries().size)
    }
    @Test fun restoresOrderActiveTitlesPixelsAsUnsavedCopiesWithoutWriteGrants() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val a = first.sessions.add(Document.create(3, 2), "Spaces and unicode ✨.aseprite", true)
        a.sourceUri = "content://provider/opaque-id"; a.path = a.sourceUri
        a.engine.document.data = UserData(text = "unsaved edit")
        val b = first.sessions.add(Document.create(4, 5), "Saved")
        first.sessions.select(a.id)
        snapshot(first)
        val second = runtime(dir, runtimes)
        assertEquals(listOf(a.id, b.id), second.sessions.documents.map { it.id })
        assertEquals(a.id, second.sessions.activeId)
        val restored = second.sessions.active
        assertEquals(a.title, restored.title)
        assertEquals("unsaved edit", restored.engine.document.data!!.text)
        assertTrue(restored.engine.dirty)
        assertTrue(second.sessions.documents[1].engine.dirty)
        assertNull(restored.path); assertEquals(a.sourceUri, restored.sourceUri)
        assertTrue(second.sessions.nextId > b.id)
    }
    @Test fun oneDamagedDraftDoesNotBlockHealthyTabsOrDeleteEvidence() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val bad = first.sessions.add(Document.create(2, 2), "Bad", true)
        val good = first.sessions.add(Document.create(3, 3), "Good", true)
        snapshot(first)
        val broken = dir.resolve("draft-${bad.id}.sdd")
        broken.writeText("damaged")
        val second = runtime(dir, runtimes)
        assertEquals(listOf(good.id), second.sessions.documents.map { it.id })
        assertNotNull(second.workspaceError)
        assertEquals("damaged", broken.readText())
        assertEquals(2, second.drafts.summaries().size)
    }
    @Test fun damagedLatestFallsBackAndRemainsUnsaved() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val tab = first.sessions.add(Document.create(2, 2), "Snapshot")
        snapshot(first); snapshot(first)
        dir.resolve("draft-${tab.id}.sdd").writeText("damaged")
        val second = runtime(dir, runtimes)
        assertEquals(tab.id, second.sessions.activeId)
        assertTrue(second.sessions.active.engine.dirty)
        assertNotNull(second.sessions.active.recoveryError)
    }
    @Test fun damagedManifestLeavesBlankWithManualRecoveryAndNeverCreatesCanvas() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        first.sessions.add(Document.create(2, 2), unsaved = true); snapshot(first)
        dir.resolve("workspace.sdw").writeText("damaged")
        val second = runtime(dir, runtimes)
        assertTrue(second.sessions.documents.isEmpty())
        assertNotNull(second.workspaceError)
        assertEquals(1, second.drafts.summaries().size)
    }
    @Test fun cancelledCloseAndInvalidDimensionsPreserveWorkspace() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val a = first.sessions.add(Document.create(16, 24), unsaved = true)
        snapshot(first)
        val before = dir.resolve("workspace.sdw").readBytes()
        assertThrows(IllegalArgumentException::class.java) { first.sessions.close(a.id) }
        assertThrows(IllegalArgumentException::class.java) { first.sessions.add(newSprite(0, 24, "")) }
        assertArrayEquals(before, dir.resolve("workspace.sdw").readBytes())
        assertEquals(a.id, first.sessions.activeId)
        assertEquals(32, first.lastNewWidth)
    }
    @Test fun lifecycleNeverReplacesDamagedIndexAndExplicitChangePreservesEvidence() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        first.sessions.add(Document.create(2, 2), unsaved = true); snapshot(first)
        val file = dir.resolve("workspace.sdw")
        file.writeText("damaged index evidence")
        val second = runtime(dir, runtimes)
        val warning = second.workspaceError
        assertNotNull(warning)
        assertFalse(second.saveWorkspace())
        assertEquals("damaged index evidence", file.readText())
        assertEquals(warning, second.workspaceError)
        second.sessions.add(Document.create(3, 3), unsaved = true)
        assertTrue(second.saveWorkspace(explicitChange = true))
        assertEquals("damaged index evidence", dir.resolve("workspace.sdw.unreadable").readText())
        assertEquals(warning, second.workspaceError)
        assertEquals(1, WorkspaceStore(dir).read()!!.tabs.size)
    }
    @Test fun partialRestoreRetainsRetryableIdsUntilExplicitChange() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val bad = first.sessions.add(Document.create(2, 2), unsaved = true)
        val good = first.sessions.add(Document.create(3, 3), unsaved = true)
        snapshot(first)
        dir.resolve("draft-${bad.id}.sdd").writeText("broken")
        val second = runtime(dir, runtimes)
        assertFalse(second.saveWorkspace())
        assertEquals(listOf(bad.id, good.id), WorkspaceStore(dir).read()!!.tabs.map { it.id })
        assertNotNull(second.workspaceError)
    }
    @Test fun closeIndexFailureLeavesTabAndDraftUnchanged() = withStorage { dir, runtimes ->
        val first = runtime(dir, runtimes)
        val tab = first.sessions.add(Document.create(16, 24), unsaved = true)
        snapshot(first)
        // A non-empty directory cannot be opened or removed as the temp file.
        val blocked = dir.resolve("workspace.sdw.tmp")
        blocked.mkdirs(); blocked.resolve("keep").writeText("block writes")
        assertFalse(first.saveWorkspace(explicitChange = true, excluding = tab.id))
        assertEquals(tab.id, first.sessions.activeId)
        assertEquals(listOf(tab.id), WorkspaceStore(dir).read()!!.tabs.map { it.id })
        assertEquals(16, first.drafts.read(tab.id).document.width)
        assertNotNull(first.workspaceError)
        blocked.deleteRecursively()
        assertTrue(first.saveWorkspace(explicitChange = true, excluding = tab.id))
        first.sessions.close(tab.id, true)
        val second = runtime(dir, runtimes)
        assertTrue(second.sessions.documents.isEmpty())
        assertEquals(1, second.drafts.summaries().size)
    }

}
