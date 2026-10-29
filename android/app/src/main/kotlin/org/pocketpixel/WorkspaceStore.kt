package org.pocketpixel

import java.io.*
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.CRC32

/** Small, atomic index of open tabs. Drafts remain independently recoverable. */
internal class WorkspaceStore(private val directory: File) {
    data class Tab(val id: Int, val dirty: Boolean)
    data class Snapshot(val tabs: List<Tab>, val activeId: Int, val width: Int, val height: Int)
    private val file get() = File(directory, "workspace.sdw")
    fun read(): Snapshot? {
        if (!file.exists()) return null
        require(file.length() in 28..1024) { "Invalid workspace size" }
        val bytes = file.readBytes()
        val input = DataInputStream(ByteArrayInputStream(bytes))
        val crc = input.readLong()
        require(CRC32().apply { update(bytes, 8, bytes.size - 8) }.value == crc) { "Workspace checksum mismatch" }
        require(input.readInt() == 0x53445731) { "Unsupported workspace version" }
        val width = input.readInt(); val height = input.readInt()
        require(width in 1..2048 && height in 1..2048) { "Invalid canvas dimensions" }
        val active = input.readInt(); val count = input.readInt()
        require(count in 0..8) { "Too many open tabs" }
        val tabs = List(count) { Tab(input.readInt().also { require(it > 0 && it < Int.MAX_VALUE - 1) }, input.readBoolean()) }
        require(input.available() == 0 && tabs.map { it.id }.toSet().size == count) { "Invalid workspace tabs" }
        require(if (tabs.isEmpty()) active == 0 else tabs.any { it.id == active }) { "Invalid active tab" }
        return Snapshot(tabs, active, width, height)
    }
    fun preserveUnreadable() {
        if (!file.exists()) return
        var backup = File(directory, "workspace.sdw.unreadable")
        var suffix = 1
        while (backup.exists()) backup = File(directory, "workspace.sdw.unreadable-${suffix++}")
        // Never remove evidence or replace a prior failed index.
        Files.copy(file.toPath(), backup.toPath())
    }
    fun write(snapshot: Snapshot) {
        check(directory.isDirectory || directory.mkdirs()) { "Workspace storage is unavailable" }
        val body = ByteArrayOutputStream()
        DataOutputStream(body).use { out ->
            out.writeInt(0x53445731); out.writeInt(snapshot.width); out.writeInt(snapshot.height)
            out.writeInt(snapshot.activeId); out.writeInt(snapshot.tabs.size)
            snapshot.tabs.forEach { out.writeInt(it.id); out.writeBoolean(it.dirty) }
        }
        val payload = body.toByteArray()
        val temp = File(file.path + ".tmp")
        try {
            FileOutputStream(temp).use { stream ->
                val out = DataOutputStream(stream)
                out.writeLong(CRC32().apply { update(payload) }.value); out.write(payload); out.flush(); stream.fd.sync()
            }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { if (temp.exists()) temp.delete() }
    }
}
