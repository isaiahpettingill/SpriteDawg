package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class RegionSelectionTest {
    private val area=mapOf<String,Any?>("x" to 0,"y" to 0,"width" to 2,"height" to 1)
    private fun fixture(indexed: Boolean=false): EditorEngine {
        val d=Document.create(4,2)
        if(indexed) { d.depth=8; d.transparentIndex=2; d.frames[0].palette=intArrayOf(0xff123456.toInt(),0xff123456.toInt(),0) }
        val c=d.editable(0,0)
        c.pixels[0]=if(indexed) 0 else 0x80123456.toInt()
        c.pixels[1]=if(indexed) 1 else 0xffaabbcc.toInt()
        return EditorEngine().also { it.replace(d) }
    }
    @Test fun exactPixelsOverlapAndUndo() {
        for(indexed in listOf(false,true)) {
            val e=fixture(indexed); val before=Aseprite.write(e.document)
            val copy=copyRegion(e.document,0,0,area)
            assertArrayEquals(before,Aseprite.write(e.document))
            assertFalse(e.dirty); assertEquals(false,e.state(false)["canUndo"])
            e.edit(area+mapOf("action" to "region","operation" to "move","dx" to 1,"dy" to 0))
            assertArrayEquals(if(indexed) intArrayOf(2,0,1) else intArrayOf(0,0x80123456.toInt(),0xffaabbcc.toInt()),e.document.resolved(0,0)!!.pixels.take(3).toIntArray())
            e.undo(); assertArrayEquals(before,Aseprite.write(e.document)); e.redo()
            e.edit(area+mapOf("action" to "region","operation" to "delete","x" to 1))
            assertArrayEquals(if(indexed) intArrayOf(2,2,2) else intArrayOf(0,0,0),e.document.resolved(0,0)!!.pixels.take(3).toIntArray())
            e.edit(area+mapOf("action" to "region","operation" to "paste","clipboard" to copy))
            assertEquals(List(2) { ByteBuffer.wrap(copy["pixels"] as ByteArray).order(ByteOrder.LITTLE_ENDIAN).getInt(it*4) },e.document.resolved(0,0)!!.pixels.take(2))
        }
    }
    @Test fun invalidBoundsAndPaletteAreAtomic() {
        for(args in listOf(mapOf("operation" to "move","dx" to -1,"dy" to 0), mapOf("operation" to "move","dx" to 3,"dy" to 0),mapOf("operation" to "delete","width" to 9))) {
            val e=fixture(); val before=Aseprite.write(e.document)
            try { e.edit(area+args+mapOf("action" to "region")); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
            assertArrayEquals(before,Aseprite.write(e.document)); assertFalse(e.dirty)
            assertEquals(false,e.state(false)["canUndo"])
        }
        val e=fixture(true); val copy=copyRegion(e.document,0,0,area)
        e.document.frames[0].palette[0]=-1
        val before=Aseprite.write(e.document)
        try { e.edit(area+mapOf("action" to "region","operation" to "paste","clipboard" to copy)); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
        assertArrayEquals(before,Aseprite.write(e.document))
    }
    @Test fun lockedHiddenAndBackgroundLayersAreProtected() {
        for(flags in listOf(1,11)) {
            val e=fixture(); e.document.layers[0].flags=flags
            try { e.edit(area+mapOf("action" to "region","operation" to "delete")); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
            assertFalse(e.dirty)
        }
        val e=fixture(); e.document.layers[0].visible=false
        try { e.edit(area+mapOf("action" to "region","operation" to "delete")); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
    }
    @Test fun otherFramesStayUnchanged() {
        val e=fixture(); e.document.frames.add(Frame(cels=mutableListOf(Cel(0,0,0,0,intArrayOf(),link=0))))
        val other=e.document.resolved(1,0)!!.pixels.copyOf()
        e.edit(area+mapOf("action" to "region","operation" to "delete"))
        assertArrayEquals(other,e.document.resolved(1,0)!!.pixels)
        e.undo(); assertArrayEquals(other,e.document.resolved(0,0)!!.pixels)
    }
    @Test fun transparentReplacementAndMalformedClipboard() {
        val e=fixture(); e.document.depth=16
        e.document.editable(0,0).pixels[0]=0x80808080.toInt()
        e.document.editable(0,0).pixels[1]=0
        val copy=copyRegion(e.document,0,0,area)
        e.document.editable(0,0).pixels[3]=-1
        e.edit(area+mapOf("action" to "region","operation" to "paste","x" to 2,"clipboard" to copy))
        assertArrayEquals(intArrayOf(0x80808080.toInt(),0),e.document.resolved(0,0)!!.pixels.sliceArray(2..3))
        val before=Aseprite.write(e.document)
        try { e.edit(area+mapOf("action" to "region","operation" to "paste","clipboard" to (copy+mapOf("width" to 2.5)))); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
        assertArrayEquals(before,Aseprite.write(e.document))
        val large=Document.create(1025,1024)
        try { copyRegion(large,0,0,mapOf("x" to 0,"y" to 0,"width" to 1025,"height" to 1024)); fail("Expected refusal") } catch(_: IllegalArgumentException) {}
    }

}
