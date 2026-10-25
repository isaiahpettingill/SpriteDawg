package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class AdvancedBrushTest {
    private fun stroke(e: EditorEngine, tool: String, extra: Map<String,Any?> = emptyMap()) = e.stroke(mapOf("tool" to tool,"points" to listOf(listOf(8,8)),"size" to 8,"color" to 0xff000000L) + extra)
    @Test fun gradientUsesConnectedRegionAndExactEndpointsIncludingAlpha() {
        val d=Document.create(5,3);val c=d.editable(0,0)
        for(y in 0..2)c.pixels[y*5+3]=0xff00ff00.toInt()
        val e=EditorEngine().apply {replace(d)}
        stroke(e,"fill",mapOf("points" to listOf(listOf(0,0)),"gradient" to true,"gradientDirection" to "horizontal","color" to 0xffff0000L,"secondaryColor" to 0x000000ffL))
        val p=e.document.composite(0)
        assertEquals(0xffff0000.toInt(),p[0]);assertEquals(0x80800080.toInt(),p[1]);assertEquals(0,p[2])
        assertEquals(0xff00ff00.toInt(),p[3]);assertEquals(0,p[4])
        e.undo();assertArrayEquals(d.composite(0),e.document.composite(0))
    }
    @Test fun gradientSinglePixelAndIndexedGrayscaleRemainNative() {
        for(depth in listOf(8,16,32)) {
            val d=Document.create(1,1);d.depth=depth
            if(depth==8)d.frames[0].palette=intArrayOf(0,0xffff0000.toInt())
            val e=EditorEngine().apply {replace(d)}
            stroke(e,"fill",mapOf("points" to listOf(listOf(0,0)),"gradient" to true,"color" to 0xffff0000L,"secondaryColor" to 0xffffffffL))
            val raw=e.document.resolved(0,0)!!.pixels.single()
            if(depth==8)assertEquals(1,raw)
            else if(depth==16)assertEquals(raw ushr 16 and 255,raw and 255)
            else assertEquals(0xffff0000.toInt(),raw)
        }
    }
    @Test fun seededSprayIsStableDenseAndUndoable() {
        val a=EditorEngine();val b=EditorEngine()
        val args=mapOf("density" to 100,"seed" to 42)
        stroke(a,"spray",args);stroke(b,"spray",args)
        val expected=a.document.composite(0)
        assertArrayEquals(expected,b.document.composite(0));assertTrue(expected.count {it!=0}>10)
        a.undo();assertTrue(a.document.composite(0).all {it==0});a.redo();assertArrayEquals(expected,a.document.composite(0))
    }
    @Test fun symmetryReflectsSprayExactlyAndDeduplicatesCenterBlur() {
        val e=EditorEngine();stroke(e,"spray",mapOf("mirrorX" to true,"mirrorY" to true,"density" to 100,"seed" to 7))
        val p=e.document.composite(0)
        for(y in 0..31)for(x in 0..31){assertEquals(p[y*32+x],p[y*32+31-x]);assertEquals(p[y*32+x],p[(31-y)*32+x])}
        val d=Document.create(3,3);d.editable(0,0).pixels[4]=0xffffffff.toInt()
        val a=EditorEngine().apply{replace(d.copyDeep())};val b=EditorEngine().apply{replace(d.copyDeep())}
        val args=mapOf("points" to listOf(listOf(1,1)),"size" to 1,"strength" to 100)
        stroke(a,"blur",args);stroke(b,"blur",args+mapOf("mirrorX" to true,"mirrorY" to true))
        assertArrayEquals(a.document.composite(0),b.document.composite(0));assertEquals(0x1cffffff,a.document.composite(0)[4])
    }
    @Test fun jumblePreservesRawHistogramAndIsDeterministic() {
        val d=Document.create(8,8);val c=d.editable(0,0)
        for(i in c.pixels.indices)c.pixels[i]=0xff000000.toInt() or i
        val a=EditorEngine().apply{replace(d.copyDeep())};val b=EditorEngine().apply{replace(d.copyDeep())}
        val args=mapOf("points" to listOf(listOf(4,4)),"size" to 8,"strength" to 100,"seed" to 17)
        stroke(a,"jumble",args);stroke(b,"jumble",args)
        val actual=a.document.resolved(0,0)!!.pixels
        assertArrayEquals(actual,b.document.resolved(0,0)!!.pixels)
        assertEquals(c.pixels.sorted(),actual.sorted());assertFalse(c.pixels.contentEquals(actual))
        a.undo();assertArrayEquals(c.pixels,a.document.resolved(0,0)!!.pixels)
    }
    @Test fun mirroredGradientRespectsDisconnectedRegionsAndReversesDirection() {
        val d=Document.create(7,1);d.editable(0,0).pixels[3]=0xff00ff00.toInt()
        val e=EditorEngine().apply{replace(d)}
        stroke(e,"fill",mapOf("points" to listOf(listOf(0,0)),"gradient" to true,"gradientDirection" to "horizontal","color" to 0xff000000L,"secondaryColor" to 0xffffffffL,"mirrorX" to true))
        val p=e.document.composite(0)
        assertEquals(p[0],p[6]);assertEquals(p[1],p[5]);assertEquals(p[2],p[4]);assertEquals(0xff00ff00.toInt(),p[3])
    }
    @Test fun selectedIndexedEntryIsNotReplacedByNearestDuplicateColor() {
        val d=Document.create(1,1);d.depth=8;d.frames[0].palette=intArrayOf(0,0xffff0000.toInt(),0xffff0000.toInt())
        val e=EditorEngine().apply{replace(d)}
        stroke(e,"pencil",mapOf("points" to listOf(listOf(0,0)),"size" to 1,"color" to 0xffff0000L,"paletteIndex" to 2))
        assertEquals(2,e.document.resolved(0,0)!!.pixels[0])
    }
}
