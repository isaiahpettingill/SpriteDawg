package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class ExportSnapshotTest {
    private fun document(direction: Int = 2): Document = Document(1, 1,
        mutableListOf(Layer("visible"), Layer("hidden", visible = false)),
        (0..3).map { i -> Frame(50 + i * 25, mutableListOf(
            Cel(0, 0, 1, 1, intArrayOf(0xff000000.toInt() or ((i + 1) shl 16))),
            Cel(0, 0, 1, 1, intArrayOf(-1))
        )) }.toMutableList(),
        mutableListOf(Tag(1, 3, direction, 3, ByteArray(3), "walk")))

    @Test fun snapshotCompositesVisibleLayersAndDetachesPixels() {
        val d = document()
        val shot = exportSnapshot(d, 2, emptyMap())
        assertEquals(listOf(2), shot["indices"])
        val bytes = (shot["frames"] as List<*>).single() as ByteArray
        assertArrayEquals(byteArrayOf(3, 0, 0, -1), bytes)
        bytes[0] = 99
        assertEquals(0xff030000.toInt(), d.frames[2].cels[0]!!.pixels.single())
    }
    @Test fun tagDirectionsTimingAndSheetMetadataAgree() {
        val expected = listOf(listOf(1,2,3), listOf(3,2,1), listOf(1,2,3,2), listOf(3,2,1,2))
        for (direction in 0..3) {
            val shot = exportSnapshot(document(direction), 0, mapOf("scope" to "tag", "tag" to 0, "animation" to true))
            assertEquals(expected[direction], shot["indices"])
            assertEquals(expected[direction].map { 50 + it * 25 }, shot["durations"])
            assertEquals(3, shot["repeat"])
        }
        val shot = exportSnapshot(document(), 0, mapOf("scope" to "tag", "tag" to 0))
        assertEquals(listOf(1,2,3), shot["indices"])
        val tag = (shot["tags"] as List<*>).single() as Map<*, *>
        assertEquals(0, tag["from"]); assertEquals(2, tag["to"])
    }
    @Test fun oversizedSnapshotFailsBeforeCompositing() {
        val d = document(); d.width = 2048; d.height = 2048
        try { exportSnapshot(d, 0, mapOf("scope" to "all")); fail("Must reject oversized export") }
        catch (_: IllegalArgumentException) { }
    }
}
