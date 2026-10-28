package org.pocketpixel

import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class NativeEditorRuntimeTest {
    @Test fun recreationSerializesOldFlushAndNewInitializationWithoutIdReuse() {
        val dir = Files.createTempDirectory("spritedawg-recreation-").toFile()
        val runtime = NativeEditorRuntime()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            val firstId = runtime.worker.submit<Int> {
                runtime.initialize(dir)
                val session = runtime.sessions.add(Document.create(2, 2), "Old Activity", true)
                session.engine.document.data = UserData(text = "old pending edit")
                runtime.pendingDrafts.mark(session.id, 0)
                session.id
            }.get(5, TimeUnit.SECONDS)
            // Simulate the old Activity's asynchronous onDestroy flush blocked
            // on I/O, while the replacement Activity requests initialization.
            val oldFlush = runtime.worker.submit {
                entered.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                runtime.pendingDrafts.flush { id ->
                    val session = runtime.sessions.documents.first { it.id == id }
                    runtime.drafts.write(id, session.title, null, session.engine.document)
                    true
                }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val newActivity = runtime.worker.submit<Int> {
                runtime.initialize(dir)
                assertEquals("old pending edit", runtime.sessions.active.engine.document.data!!.text)
                // The replacement retains open sessions and allocates a fresh ID,
                // rather than scanning before the old write and reusing its ID.
                runtime.sessions.add(Document.create(2, 2), "New Activity", true).id
            }
            assertFalse(newActivity.isDone)
            release.countDown()
            oldFlush.get(5, TimeUnit.SECONDS)
            val secondId = newActivity.get(5, TimeUnit.SECONDS)
            assertNotEquals(firstId, secondId)
            runtime.worker.submit {
                val first = runtime.sessions.documents.first { it.id == firstId }
                first.engine.document.data = UserData(text = "new Activity latest edit")
                runtime.pendingDrafts.mark(first.id, 10)
            }.get(5, TimeUnit.SECONDS)
            // Even a delayed old-Activity lifecycle callback sees the shared
            // latest model, not a stale separately-owned snapshot.
            runtime.worker.submit {
                runtime.pendingDrafts.flush { id ->
                    val session = runtime.sessions.documents.first { it.id == id }
                    runtime.drafts.write(id, session.title, null, session.engine.document)
                    true
                }
            }.get(5, TimeUnit.SECONDS)
            assertEquals("new Activity latest edit", DraftStore(dir).read(firstId).document.data!!.text)
            assertFalse(dir.resolve("draft-$firstId.sdd.tmp").exists())
        } finally {
            release.countDown()
            runtime.worker.shutdownNow()
            runtime.worker.awaitTermination(5, TimeUnit.SECONDS)
            dir.deleteRecursively()
        }
    }

    @Test fun recreationRetainsUnwrittenEditsAndPendingIdsAfterStorageFailure() {
        val dir = Files.createTempDirectory("spritedawg-recreation-full-").toFile()
        val runtime = NativeEditorRuntime()
        try {
            runtime.worker.submit {
                runtime.initialize(dir)
                val session = runtime.sessions.add(Document.create(2, 2), unsaved = true)
                session.engine.document.data = UserData(text = "not yet durable")
                runtime.pendingDrafts.mark(session.id, 100)
                runtime.pendingDrafts.flush { false }
                // A new Activity calls initialize on this same process runtime.
                runtime.initialize(dir)
                assertSame(session, runtime.sessions.active)
                assertTrue(runtime.pendingDrafts.contains(session.id))
                assertEquals("not yet durable", runtime.sessions.active.engine.document.data!!.text)
                assertTrue(runtime.sessions.active.engine.dirty)
            }.get(5, TimeUnit.SECONDS)
        } finally {
            runtime.worker.shutdownNow()
            runtime.worker.awaitTermination(5, TimeUnit.SECONDS)
            dir.deleteRecursively()
        }
    }
    @Test fun recreationDoesNotReplayViewButFreshLaunchAndNewProcessDo() {
        val runtime = NativeEditorRuntime()
        val restartedProcess = NativeEditorRuntime()
        try {
            assertTrue(runtime.shouldEnqueueStartup(false))
            assertFalse(runtime.shouldEnqueueStartup(true))
            assertFalse(runtime.shouldEnqueueStartup(true))
            // A genuinely new launch is not a configuration-state restoration.
            assertTrue(runtime.shouldEnqueueStartup(false))
            // After process death there is no retained in-memory import.
            assertTrue(restartedProcess.shouldEnqueueStartup(true))
        } finally {
            runtime.worker.shutdownNow()
            restartedProcess.worker.shutdownNow()
        }
    }

}
