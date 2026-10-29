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

    private var workspace: WorkspaceStore? = null
    var lastNewWidth = 32
    var lastNewHeight = 32
    private var restoreWarning: String? = null
    private var workspaceWriteError: String? = null
    val workspaceError get() = workspaceWriteError ?: restoreWarning
    private var preserveUnreadableManifest = false
    private var incompleteRestore = false
    fun saveWorkspace(explicitChange: Boolean = false, excluding: Int? = null): Boolean {
        // A lifecycle callback is not consent to replace a failed-read index.
        // Keep retryable tab IDs until the user actually changes the workspace.
        if (incompleteRestore && !explicitChange) return false
        try {
            if (preserveUnreadableManifest) {
                checkNotNull(workspace).preserveUnreadable()
                preserveUnreadableManifest = false
            }
            val documents = sessions.documents.filter { it.id != excluding }
            val activeId = if (documents.any { it.id == sessions.activeId }) sessions.activeId
                else documents.getOrNull(sessions.documents.indexOfFirst { it.id == excluding }.coerceAtMost(documents.lastIndex))?.id ?: 0
            checkNotNull(workspace).write(WorkspaceStore.Snapshot(
                documents.map { WorkspaceStore.Tab(it.id, it.engine.dirty) },
                activeId, lastNewWidth, lastNewHeight,
            ))
            workspaceWriteError = null
            incompleteRestore = false
            return true
        } catch (e: Exception) {
            workspaceWriteError = "Open tabs could not be remembered: ${e.message}. Save a copy before leaving."
            return false
        }
    }

    fun initialize(directory: File, resolveLegacyTitle: (String?, String) -> String? = { _, _ -> null }) {
        if (initialized) return
        val candidate = DraftStore(directory, resolveLegacyTitle = resolveLegacyTitle)
        val saved = candidate.summaries()
        saved.forEach { item -> sessions.nextId = maxOf(sessions.nextId, (item["id"] as Int) + 1) }
        workspace = WorkspaceStore(directory)
        val snapshot = try { workspace!!.read() } catch (e: Exception) {
            incompleteRestore = true
            preserveUnreadableManifest = true
            restoreWarning = "Open tabs could not be restored: ${e.message}. Internal drafts are still available."
            null
        }
        snapshot?.let { savedWorkspace ->
            lastNewWidth = savedWorkspace.width; lastNewHeight = savedWorkspace.height
            savedWorkspace.tabs.forEach { tab ->
                sessions.nextId = maxOf(sessions.nextId, tab.id + 1)
                try {
                    val draft = candidate.read(tab.id)
                    val restored = sessions.restoreDecoded(listOf(tab.id to draft.document)).single()
                    restored.title = draft.title
                    restored.titleNeedsRefresh = draft.titleNeedsRefresh
                    restored.sourceUri = draft.sourceUri
                    // A snapshot is not a current provider write grant. Save As
                    // safely lets the user choose a destination after restarting.
                    restored.path = null
                    // Restored snapshots have no write target: keep even formerly
                    // clean tabs unsaved, so close cannot silently discard the
                    // only surviving copy of a now-missing external project.
                    if (draft.fallback) restored.recoveryError = "The latest draft was damaged; the previous good snapshot was recovered. Save a copy now."
                } catch (e: Exception) {
                    incompleteRestore = true
                    restoreWarning = "Some tabs could not be restored. Their drafts were retained; use Internal drafts to retry."
                }
            }
            if (sessions.documents.any { it.id == savedWorkspace.activeId }) sessions.select(savedWorkspace.activeId)
        }
        store = candidate
    }
}

