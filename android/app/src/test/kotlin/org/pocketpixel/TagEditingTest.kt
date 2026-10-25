package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class TagEditingTest {
    private fun engine(): EditorEngine {
        val d = Document.create(8, 4)
        d.addFrame(0, false); d.addFrame(1, false)
        val properties = UserProperties.write(listOf(Property("damage", 6, ByteArray(0)).withText("12")))
        d.tags.add(Tag(0, 1, 2, 7, byteArrayOf(11,22,33), "Walk", UserData("{\"speed\":4}", 0x80123456.toInt(), properties)))
        return EditorEngine().apply { replace(d); select(mapOf("frame" to 2)) }
    }
    @Test fun updatingRangeDirectionAndRepeatPreservesMetadataAcrossSaveAndUndo() {
        val e = engine(); val original = Aseprite.write(e.document)
        e.edit(mapOf("action" to "updateTag", "index" to 0, "name" to "Jump α", "from" to 1, "to" to 2, "direction" to 3, "repeat" to 65535))
        assertEquals(2, e.frame)
        val restored = Aseprite.read(Aseprite.write(e.document)).tags.single()
        assertEquals("Jump α", restored.name); assertEquals(1, restored.from); assertEquals(2, restored.to)
        assertEquals(3, restored.direction); assertEquals(65535, restored.repeat)
        assertArrayEquals(byteArrayOf(11,22,33), restored.color)
        assertEquals("{\"speed\":4}", restored.data!!.text); assertEquals(0x80123456.toInt(), restored.data!!.color)
        assertEquals("12", UserProperties.read(restored.data!!.properties).single().text())
        e.undo(); assertArrayEquals(original, Aseprite.write(e.document)); assertFalse(e.state(false)["canUndo"] as Boolean)
        e.redo(); assertEquals("Jump α", e.document.tags.single().name); assertEquals(2, e.frame)
    }
    @Test fun duplicateIsIndependentAndSingleUndoTransaction() {
        val e = engine()
        e.edit(mapOf("action" to "duplicateTag", "index" to 0))
        val source = e.document.tags[0]; val copy = e.document.tags[1]
        assertEquals(source.name, copy.name); assertEquals(source.from, copy.from); assertEquals(source.to, copy.to)
        assertEquals(source.direction, copy.direction); assertEquals(source.repeat, copy.repeat)
        assertNotSame(source.color, copy.color); assertNotSame(source.data!!.properties, copy.data!!.properties)
        assertArrayEquals(source.data!!.properties, copy.data!!.properties)
        copy.color[0] = 99
        assertEquals(11, source.color[0].toInt())
        val reopened = Aseprite.read(Aseprite.write(e.document))
        assertEquals(11, reopened.tags[0].color[0].toInt()); assertEquals(99, reopened.tags[1].color[0].toInt())
        assertEquals(source.data!!.text, reopened.tags[1].data!!.text)
        e.undo(); assertEquals(1, e.document.tags.size); assertFalse(e.state(false)["canUndo"] as Boolean)
        e.redo(); assertEquals(2, e.document.tags.size); assertEquals(2, e.frame)
    }
    @Test fun duplicateOverridesAndPartialUpdateHaveNoNamingConventions() {
        val e = engine()
        e.edit(mapOf("action" to "duplicateTag", "index" to 0, "name" to "", "from" to 2, "to" to 2))
        assertEquals("", e.document.tags[1].name); assertEquals(2, e.document.tags[1].from)
        e.edit(mapOf("action" to "updateTag", "index" to 1, "repeat" to 0))
        val tag = e.document.tags[1]
        assertEquals("", tag.name); assertEquals(2, tag.to); assertEquals(2, tag.direction); assertEquals(0, tag.repeat)
        assertEquals("Walk", e.document.tags[0].name)
    }
    @Test fun invalidEditsAreRejectedWithoutHistoryOrPartialMutation() {
        val invalid = listOf(
            mapOf("index" to -1), mapOf("index" to 5), mapOf("from" to 2, "to" to 1),
            mapOf("to" to 3), mapOf("from" to -1), mapOf("direction" to 4),
            mapOf("repeat" to -1), mapOf("repeat" to 65536), mapOf("repeat" to 1.5),
            mapOf("name" to "é".repeat(32768)), mapOf("name" to null), mapOf("index" to 0.5)
        )
        for (fields in invalid) {
            val e = engine(); val original = Aseprite.write(e.document)
            try { e.edit(mapOf("action" to "updateTag", "index" to 0) + fields); fail("Must reject $fields") }
            catch (_: IllegalArgumentException) { }
            assertArrayEquals(original, Aseprite.write(e.document)); assertFalse(e.dirty)
            assertFalse(e.state(false)["canUndo"] as Boolean); assertEquals(2, e.frame)
        }
    }
    @Test fun newTagsSupportRepeatAndRejectInvalidDirectionsRatherThanClamping() {
        val e = engine()
        e.edit(mapOf("action" to "addTag", "name" to "Whatever I Want", "from" to 0, "to" to 2, "direction" to 1, "repeat" to 42))
        assertEquals(42, e.document.tags.last().repeat)
        try { e.edit(mapOf("action" to "addTag", "direction" to 99)); fail("Must reject") }
        catch (_: IllegalArgumentException) { }
        assertEquals(2, e.document.tags.size)
    }
}
