package org.pocketpixel

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.CRC32

/** App-private drafts, not original save targets. The previous validated generation
 * survives a damaged/interrupted latest write. All calls belong to one worker. */
internal class DraftStore(
    private val directory: File,
    private val capacity: Long = 256L * 1024 * 1024,
    private val maximumDrafts: Int = 64,
    private val resolveLegacyTitle: (String?, String) -> String? = { _, _ -> null },
) {
    data class Draft(
        val id: Int,
        val title: String,
        val sourceUri: String?,
        val updatedAt: Long,
        val document: Document,
        val fallback: Boolean = false,
        val titleNeedsRefresh: Boolean = false,
        val titleRefreshed: Boolean = false,
    ) {
        fun summary(): Map<String, Any?> = mapOf(
            "id" to id, "title" to title, "updatedAt" to updatedAt,
            "width" to document.width, "height" to document.height,
            "frames" to document.frames.size, "fallback" to fallback,
        )
    }

    private val cache = linkedMapOf<Int, Map<String, Any?>>()
    private var initialized = false
    private fun current(id: Int) = File(directory, "draft-$id.sdd")
    private fun previous(id: Int) = File(directory, "draft-$id.sdd.previous")
    private fun legacy(id: Int) = File(directory, if (id == 0) "recovery.aseprite" else "recovery-$id.aseprite")
    private fun ids(): Set<Int> = directory.listFiles().orEmpty().mapNotNull { file ->
        if (!file.isFile) null else when {
            file.name == "recovery.aseprite" || file.name == "recovery.aseprite.bak" -> 0
            else -> Regex("(?:draft-([0-9]+)\\.sdd(?:\\.previous)?|recovery-([0-9]+)\\.aseprite(?:\\.bak)?)")
                .matchEntire(file.name)?.let { (it.groupValues[1].ifEmpty { it.groupValues[2] }).toIntOrNull() }
        }
    }.filter { it >= 0 && it < Int.MAX_VALUE - 1 }.toSet()

    fun summaries(refresh: Boolean = false): List<Map<String, Any?>> {
        if (!initialized || refresh) {
            check(directory.isDirectory || directory.mkdirs()) { "Internal draft storage is unavailable" }
            // Temporary files were never committed. Remove interrupted writes,
            // never a committed draft or its last-good generation.
            directory.listFiles().orEmpty().filter {
                it.isFile && Regex("draft-[0-9]+\\.sdd(?:\\.previous)?\\.tmp").matches(it.name)
            }.forEach { it.delete() }
            cache.clear()
            ids().forEach { id ->
                cache[id] = try { read(id).summary() } catch (e: Exception) {
                    mapOf("id" to id, "title" to "Unreadable draft $id", "updatedAt" to
                        listOf(current(id), previous(id), legacy(id)).maxOf { it.lastModified() },
                        "error" to "This draft could not be read. Other drafts are unaffected; keep it or explicitly delete it.")
                }
            }
            initialized = true
        }
        return cache.values.sortedByDescending { (it["updatedAt"] as? Number)?.toLong() ?: 0L }
    }

    fun read(id: Int): Draft {
        require(id >= 0 && id < Int.MAX_VALUE - 1) { "Invalid draft ID" }
        val candidates = listOf(current(id), previous(id), File(legacy(id).path + ".bak"), legacy(id))
        var failure: Exception? = null
        candidates.forEachIndexed { index, file ->
            if (file.isFile) try {
                require(file.length() <= Aseprite.MAX_FILE + 32768L) { "Draft exceeds the safety limit" }
                val draft = if (index < 2) decode(file.readBytes(), id) else Draft(
                    id, "Recovered $id", null, file.lastModified(), Aseprite.read(file.readBytes()),
                )
                val resolved = if (draft.titleNeedsRefresh) try {
                    resolveLegacyTitle(draft.sourceUri, draft.title)
                } catch (_: Exception) { null } else null
                return draft.copy(
                    fallback = index == 1 || index == 2,
                    title = resolved ?: draft.title,
                    titleNeedsRefresh = draft.titleNeedsRefresh && resolved == null,
                    titleRefreshed = resolved != null,
                )
            } catch (e: Exception) { failure = e }
        }
        throw IllegalStateException("Draft $id has no readable snapshot", failure)
    }

    fun write(id: Int, title: String, sourceUri: String?, document: Document, updatedAt: Long = System.currentTimeMillis(), titleNeedsRefresh: Boolean = false) {
        require(id > 0 && id < Int.MAX_VALUE - 1) { "Invalid draft ID" }
        summaries()
        require(id in cache || cache.size < maximumDrafts) { "Internal draft limit reached ($maximumDrafts). Save or explicitly delete an older draft; no drafts were removed." }
        val bytes = Aseprite.write(document)
        Aseprite.read(bytes) // Never replace a last-good generation with invalid output.
        val draft = Draft(id, title.take(512), sourceUri?.take(8192), updatedAt, document, titleNeedsRefresh = titleNeedsRefresh)
        val encoded = encode(draft, bytes)
        val old = listOf(current(id), previous(id)).firstOrNull { candidate ->
            candidate.isFile && candidate.length() <= Aseprite.MAX_FILE + 32768L && try { decode(candidate.readBytes(), id); true } catch (_: Exception) { false }
        }
        val occupied = directory.listFiles().orEmpty().filter { it.isFile &&
            (it.name.startsWith("draft-") || it.name.startsWith("recovery")) }.sumOf { it.length() }
        // Account for both temporary files at peak, not just steady-state size.
        require(occupied + encoded.size + (old?.length() ?: 0L) <= capacity) {
            "Internal draft storage is full. Save a copy or explicitly delete an older draft; no drafts were removed."
        }
        if (old != null && old != previous(id)) atomic(previous(id), old.readBytes())
        atomic(current(id), encoded)
        cache[id] = draft.summary()
        // A committed modern envelope supersedes this ID's legacy recovery only.
        listOf(legacy(id), File(legacy(id).path + ".bak")).forEach { if (it.exists()) it.delete() }
    }

    fun delete(id: Int) {
        summaries()
        // Remove current first: on an interrupted explicit delete the older copy
        // may still be offered, but no new writer can resurrect it in this queue.
        listOf(current(id), previous(id), legacy(id), File(legacy(id).path + ".bak"),
            File(current(id).path + ".tmp"), File(previous(id).path + ".tmp")).forEach {
            check(!it.exists() || it.delete()) { "Draft could not be removed; it has been retained." }
        }
        cache.remove(id)
    }

    private fun atomic(file: File, bytes: ByteArray) {
        val temp = File(file.path + ".tmp")
        try {
            FileOutputStream(temp).use { output -> output.write(bytes); output.fd.sync() }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { if (temp.exists()) temp.delete() }
    }

    private fun encode(draft: Draft, bytes: ByteArray): ByteArray {
        val body = ByteArrayOutputStream()
        DataOutputStream(body).use { out ->
            out.writeInt(0x53444432); out.writeInt(draft.id); out.writeLong(draft.updatedAt)
            out.writeUTF(draft.title); out.writeUTF(draft.sourceUri ?: "")
            out.writeBoolean(draft.titleNeedsRefresh)
            out.writeInt(bytes.size); out.write(bytes)
        }
        val payload = body.toByteArray()
        val result = ByteArrayOutputStream()
        DataOutputStream(result).use { out -> out.writeLong(CRC32().apply { update(payload) }.value); out.write(payload) }
        return result.toByteArray()
    }

    private fun decode(bytes: ByteArray, expectedId: Int): Draft {
        require(bytes.size in 32..(Aseprite.MAX_FILE + 32768)) { "Invalid draft size" }
        val input = DataInputStream(ByteArrayInputStream(bytes))
        val checksum = input.readLong()
        require(CRC32().apply { update(bytes, 8, bytes.size - 8) }.value == checksum) { "Draft checksum mismatch" }
        val format = input.readInt()
        require(format == 0x53444431 || format == 0x53444432) { "Unsupported draft format" }
        val id = input.readInt(); require(id == expectedId) { "Draft identity mismatch" }
        val updatedAt = input.readLong(); val title = input.readUTF(); val source = input.readUTF()
        val titleNeedsRefresh = if (format == 0x53444431) true else input.readBoolean()
        val size = input.readInt()
        require(size in 128..Aseprite.MAX_FILE && size == input.available()) { "Invalid draft payload" }
        val document = ByteArray(size).also { input.readFully(it) }.let(Aseprite::read)
        return Draft(id, title, source.ifEmpty { null }, updatedAt, document, titleNeedsRefresh = titleNeedsRefresh)
    }
}

/** Worker-confined dirty-ID set: coalesces rapid edits without capturing stale
 * documents or relying on whichever tab happens to be selected when it runs. */
internal class DraftPending {
    private val ids = linkedSetOf<Int>()
    private var firstChange: Long? = null
    fun mark(id: Int, now: Long) { if (firstChange == null) firstChange = now; ids.add(id) }
    fun delay(now: Long): Long = minOf(600L, (2000L - (now - (firstChange ?: now))).coerceAtLeast(0))
    fun forget(id: Int) { ids.remove(id); if (ids.isEmpty()) firstChange = null }
    fun contains(id: Int) = id in ids
    fun flush(write: (Int) -> Boolean) {
        try { ids.toList().forEach { if (write(it)) ids.remove(it) } }
        finally {
            // Failed IDs stay retryable, but the next edit starts a fresh bounded
            // debounce window instead of retrying expensive encoding every stroke.
            firstChange = null
        }
    }
}
