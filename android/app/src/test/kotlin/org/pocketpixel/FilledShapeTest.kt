package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class FilledShapeTest {
    private fun draw(e: EditorEngine, tool: String, points: List<List<Int>>, filled: Boolean = true) = e.stroke(mapOf("tool" to tool, "points" to points, "filled" to filled, "color" to 0xffe53935L, "size" to 1))
    @Test fun rectangleFillsInteriorReversedDragsMatchAndUndoIsOneStep() {
        val a = EditorEngine(); val b = EditorEngine()
        draw(a, "rectangle", listOf(listOf(2,3),listOf(7,8)))
        draw(b, "rectangle", listOf(listOf(7,8),listOf(2,3)))
        assertArrayEquals(a.document.composite(0),b.document.composite(0))
        assertEquals(36,a.document.composite(0).count { it ushr 24 != 0 })
        a.undo(); assertTrue(a.document.composite(0).all { it == 0 }); assertFalse(a.state(false)["canUndo"] as Boolean)
        a.redo(); assertEquals(36,a.document.composite(0).count { it ushr 24 != 0 })
    }
    @Test fun filledEllipseIsSymmetricAndOutlineRemainsDefault() {
        val a = EditorEngine(); val b = EditorEngine()
        draw(a,"ellipse",listOf(listOf(2,2),listOf(10,8)))
        draw(b,"ellipse",listOf(listOf(10,8),listOf(2,2)))
        val p=a.document.composite(0)
        assertArrayEquals(p,b.document.composite(0)); assertNotEquals(0,p[5*32+6]); assertEquals(0,p[2*32+2])
        for(y in 2..8) for(x in 2..10) assertEquals(p[y*32+x],p[(10-y)*32+12-x])
        val outline=EditorEngine(); draw(outline,"rectangle",listOf(listOf(2,2),listOf(10,8)),false)
        assertEquals(0,outline.document.composite(0)[5*32+6])
    }
    @Test fun degenerateAndTwoPixelEllipsesAreNonempty() {
        for ((end,count) in listOf(listOf(0,0) to 1,listOf(1,1) to 4,listOf(0,4) to 5,listOf(4,0) to 5)) {
            val e=EditorEngine();draw(e,"ellipse",listOf(listOf(0,0),end))
            assertEquals(count,e.document.composite(0).count { it ushr 24 != 0 })
        }
    }
    @Test fun filledShapesClipAndRespectIndexedAndGrayscaleColors() {
        for(depth in listOf(8,16,32)) for(tool in listOf("rectangle","ellipse")) {
            val d=Document.create(4,4);d.depth=depth
            if(depth==8) d.frames[0].palette=intArrayOf(0,0xffe53935.toInt())
            val e=EditorEngine().apply { replace(d) }
            draw(e,tool,listOf(listOf(-10,-10),listOf(10,10)))
            assertEquals(16,e.document.composite(0).count { it ushr 24 != 0 })
            val stored=e.document.resolved(0,0)!!.pixels[0]
            if(depth==8) assertEquals(1,stored)
            if(depth==16) assertEquals(stored ushr 16 and 255,stored and 255)
        }
    }
}
