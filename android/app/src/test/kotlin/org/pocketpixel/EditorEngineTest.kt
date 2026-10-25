package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class EditorEngineTest {
    private fun stroke(e: EditorEngine, tool: String, points: List<List<Int>>, color: Long = 0xffff3300L) = e.stroke(mapOf("tool" to tool,"points" to points,"color" to color,"size" to 1))
    @Test fun strokesInterpolateAndUndoExactly() {
        val e=EditorEngine(); stroke(e,"pencil",listOf(listOf(0,0),listOf(4,4)))
        for(i in 0..4) assertEquals(0xffff3300.toInt(),e.document.composite(0)[i*32+i])
        e.undo(); assertTrue(e.document.composite(0).all { it==0 })
        e.redo(); assertEquals(0xffff3300.toInt(),e.document.composite(0)[0])
    }
    @Test fun errorsDoNotChangeDocumentOrHistory() {
        val e=EditorEngine()
        try { e.edit(mapOf("action" to "deleteLayer")); fail("must reject") } catch(_: IllegalArgumentException) {}
        assertEquals(1,e.document.layers.size); assertFalse(e.state(false)["canUndo"] as Boolean)
        assertFalse(e.dirty)
    }
    @Test fun hiddenAndLockedLayersCannotBeDrawn() {
        val e=EditorEngine(); e.edit(mapOf("action" to "layerVisibility","visible" to false))
        try { stroke(e,"pencil",listOf(listOf(0,0))); fail("must reject") } catch(_: IllegalArgumentException) {}
        assertNull(e.document.frames[0].cels[0])
    }
    @Test fun fillAndEraserAreActualPixelEdits() {
        val e=EditorEngine(); stroke(e,"fill",listOf(listOf(0,0)))
        assertTrue(e.document.composite(0).all { it==0xffff3300.toInt() })
        stroke(e,"eraser",listOf(listOf(2,2)))
        assertEquals(0,e.document.composite(0)[66]); assertEquals(0xffff3300.toInt(),e.document.composite(0)[67])
    }
    @Test fun everyShapeDrawsAndDoesNotEscapeCanvas() {
        for(tool in listOf("line","rectangle","ellipse")) {
            val e=EditorEngine(); stroke(e,tool,listOf(listOf(0,0),listOf(10,8)))
            assertTrue(e.document.composite(0).any { it!=0 })
            assertEquals(0,e.document.composite(0).last())
        }
    }
    @Test fun frameAndLayerOperationsPreserveMetadata() {
        val e=EditorEngine(); e.edit(mapOf("action" to "userData","target" to "sprite","text" to "{\"strength\":12}"))
        stroke(e,"pencil",listOf(listOf(0,0)))
        e.edit(mapOf("action" to "duplicateFrame")); assertEquals(1,e.frame)
        e.edit(mapOf("action" to "addLayer","name" to "Ink")); assertEquals(1,e.layer)
        e.edit(mapOf("action" to "addTag","name" to "Walk","from" to 0,"to" to 1))
        val decoded=Aseprite.read(Aseprite.write(e.document))
        assertEquals("{\"strength\":12}",decoded.data?.text)
        assertEquals("Walk",decoded.tags.single().name); assertEquals(2,decoded.frames.size)
        assertEquals(0xffff3300.toInt(),decoded.composite(1)[0])
    }
    @Test fun stateIsRgbaNotArgbAndIncludesMetadata() {
        val e=EditorEngine(); stroke(e,"pencil",listOf(listOf(0,0)),0x80123456L)
        val bytes=e.state(false)["pixels"] as ByteArray
        assertArrayEquals(byteArrayOf(0x12,0x34,0x56,0x80.toByte()),bytes.copyOfRange(0,4))
    }
    @Test fun invalidMetadataEditIsAtomic() {
        val e=EditorEngine()
        try { e.edit(mapOf("action" to "userData","target" to "sprite","text" to "é".repeat(32768))); fail("must reject") } catch(_: IllegalArgumentException) {}
        assertNull(e.document.data); assertFalse(e.dirty)
    }
}
