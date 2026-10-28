package org.pocketpixel

import java.io.File
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.ScheduledThreadPoolExecutor

/** One process-wide model and storage queue, retained across Activity recreation.
 * An old Activity's final flush and a new Activity's init cannot race disk writes,
 * ID allocation, or each other's edits. Retaining the model also keeps edits alive
 * when storage is full during recreation. Only the owning worker may access state. */
internal class NativeEditorRuntime {
    val worker = ScheduledThreadPoolExecutor(1).apply {
        removeOnCancelPolicy = true
        setExecuteExistingDelayedTasksAfterShutdownPolicy(false)
    }
    val sessions = EditorSessions()
    val pendingDrafts = DraftPending()
    var draftTask: ScheduledFuture<*>? = null
    // Main-thread-only launch bookkeeping is separate from worker-owned model
    // state. A recreated Activity must not replay an already-consumed VIEW.
    private var configuredActivity = false
    fun shouldEnqueueStartup(restoredActivity: Boolean): Boolean {
        val enqueue = !restoredActivity || !configuredActivity
        configuredActivity = true
        return enqueue
    }
    private var store: DraftStore? = null
    val initialized get() = store != null
    val drafts get() = checkNotNull(store) { "Editor storage has not initialized" }

    fun initialize(directory: File) {
        if (initialized) return
        val candidate = DraftStore(directory)
        val saved = candidate.summaries()
        saved.forEach { item -> sessions.nextId = maxOf(sessions.nextId, (item["id"] as Int) + 1) }
        if (saved.isNotEmpty()) {
            sessions.documents.clear()
            val blank = EditorSession(sessions.nextId++)
            sessions.configure(blank)
            sessions.documents.add(blank)
            sessions.activeId = blank.id
        }
        store = candidate
    }
}
