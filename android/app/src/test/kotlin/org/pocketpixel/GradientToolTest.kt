package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class GradientToolTest {
    private fun canvas(depth: Int = 32): EditorEngine {
        val d=Document.create(5,3); d.depth=depth
        return EditorEngine().apply { replace(d) }
    }
    private fun args(extra: Map<String,Any?> = emptyMap()) = mapOf(
        "tool" to "gradient", "points" to listOf(listOf(1,1),listOf(3,1)),
        "color" to 0xffff0000L, "secondaryColor" to 0xff0000ffL
    ) + extra
    @Test fun endpointClampingAndOneUndo() {
        val e=canvas(); e.stroke(args())
        val row=intArrayOf(0xffff0000.toInt(),0xffff0000.toInt(),0xff800080.toInt(),0xff0000ff.toInt(),0xff0000ff.toInt())
        assertArrayEquals(row+row+row,e.document.composite(0))
        val after=Aseprite.write(e.document);e.undo()
        assertTrue(e.document.composite(0).all { it==0 });e.redo()
        assertArrayEquals(after,Aseprite.write(e.document))
    }
    @Test fun alphaIsBlendedOnceAndSymmetryIgnored() {
        val a=canvas();val b=canvas()
        a.document.editable(0,0).pixels.fill(0xff00ff00.toInt())
        b.document.editable(0,0).pixels.fill(0xff00ff00.toInt())
        val p=args(mapOf("color" to 0x00ff0000L,"secondaryColor" to 0x800000ffL))
        a.stroke(p);b.stroke(p+mapOf("mirrorX" to true,"mirrorY" to true,"mirrorDiagonal" to true,"mirrorAntiDiagonal" to true,"size" to 32))
        assertArrayEquals(a.document.composite(0),b.document.composite(0))
        assertEquals(0xff00ff00.toInt(),a.document.composite(0)[0])
        assertEquals(over(0xff00ff00.toInt(),0x800000ff.toInt()),a.document.composite(0)[4])
    }
    @Test fun tapDoesNotDirtyOrAddUndo() {
        val e=canvas();val before=Aseprite.write(e.document)
        e.stroke(args(mapOf("points" to listOf(listOf(1,1),listOf(1,1)))))
        assertArrayEquals(before,Aseprite.write(e.document))
        assertEquals(false,e.state(false)["dirty"]);assertEquals(false,e.state(false)["canUndo"])
    }
    @Test fun indexedBlendsBeforeQuantizingAndPreservesDuplicateUnderTransparentInk() {
        val e=canvas(8)
        e.document.frames[0].palette=intArrayOf(0,0xff00ff00.toInt(),0xff800080.toInt(),0xff007f80.toInt(),0xff00ff00.toInt())
        e.document.editable(0,0).pixels.fill(4)
        e.stroke(args(mapOf("color" to 0x000000ffL,"secondaryColor" to 0x800000ffL,"paletteIndex" to 2)))
        assertEquals(4,e.document.resolved(0,0)!!.pixels[0])
        assertEquals(3,e.document.resolved(0,0)!!.pixels[4])
        e.undo();assertTrue(e.document.resolved(0,0)!!.pixels.all { it==4 })
    }
    @Test fun diagonalReverseMatchesAndLargeCoordinatesDoNotOverflow() {
        val a=canvas();val b=canvas()
        a.stroke(args(mapOf("points" to listOf(listOf(0,0),listOf(4,2)))))
        b.stroke(args(mapOf("points" to listOf(listOf(4,2),listOf(0,0)),"color" to 0xff0000ffL,"secondaryColor" to 0xffff0000L)))
        assertArrayEquals(a.document.composite(0),b.document.composite(0))
        val c=canvas();c.stroke(args(mapOf("points" to listOf(listOf(-8192,-8192),listOf(8192,8192)))))
        assertEquals(0xff800080.toInt(),c.document.composite(0)[0])
    }
    @Test fun previewPreservesDocumentAndMatchesCommit() {
        val e=canvas();val before=Aseprite.write(e.document);val p=e.previewStroke(args())
        assertArrayEquals(before,Aseprite.write(e.document));assertEquals(false,e.state(false)["canUndo"])
        e.stroke(args());assertArrayEquals(p["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
    }
}
