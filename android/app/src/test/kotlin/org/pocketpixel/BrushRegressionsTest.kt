package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class BrushRegressionsTest {
    private fun canvas(depth: Int=32): EditorEngine {
        val d=Document.create(16,16);d.depth=depth
        return EditorEngine().apply{replace(d)}
    }
    private fun stroke(e: EditorEngine,tool: String,extra: Map<String,Any?> = emptyMap()) = e.stroke(mapOf("tool" to tool,"points" to listOf(listOf(8,8)),"size" to 1,"color" to 0x80ff0000L)+extra)
    @Test fun previewLeavesOriginalAndHistoryUntouched() {
        val e=canvas();val before=Aseprite.write(e.document);val state=e.state(false)
        val args=mapOf("tool" to "airbrush","points" to listOf(listOf(8,8),listOf(8,8)),"size" to 9,"strength" to 20,"color" to 0xffff0000L)
        val preview=e.previewStroke(args)
        assertArrayEquals(before,Aseprite.write(e.document))
        assertEquals(state["dirty"],e.state(false)["dirty"])
        assertEquals(state["canUndo"],e.state(false)["canUndo"])
        assertEquals(state["canRedo"],e.state(false)["canRedo"])
        e.stroke(args);assertArrayEquals(preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
    }
    @Test fun paintToolsBlendOverExistingPixelsAndUndo() {
        for(tool in listOf("pencil","line","rectangle","ellipse","fill")) {
            val e=canvas();e.document.editable(0,0).pixels.fill(0xff0000ff.toInt())
            stroke(e,tool,mapOf("points" to listOf(listOf(8,8),listOf(8,8)),"mirrorX" to true,"mirrorY" to true))
            assertEquals(tool,over(0xff0000ff.toInt(),0x80ff0000.toInt()),e.document.resolved(0,0)!!.pixels[136])
            e.undo();assertEquals(0xff0000ff.toInt(),e.document.resolved(0,0)!!.pixels[136])
        }
    }
    @Test fun overlappingPencilStampsBlendOncePerGesture() {
        val e=canvas()
        stroke(e,"pencil",mapOf("points" to listOf(listOf(7,8),listOf(8,8),listOf(7,8)),"size" to 3))
        assertEquals(0x80ff0000.toInt(),e.document.resolved(0,0)!!.pixels[136])
        stroke(e,"pencil");assertEquals(192,e.document.resolved(0,0)!!.pixels[136] ushr 24)
    }
    @Test fun transparentPaintDoesNotErase() {
        val e=canvas();e.document.editable(0,0).pixels[136]=0xff0000ff.toInt()
        stroke(e,"pencil",mapOf("color" to 0x00ff0000L));assertEquals(0xff0000ff.toInt(),e.document.resolved(0,0)!!.pixels[136])
        stroke(e,"eraser");assertEquals(0,e.document.resolved(0,0)!!.pixels[136])
    }
    @Test fun stationarySprayAddsDispersedDots() {
        val a=canvas();val b=canvas();val args=mapOf("size" to 12,"density" to 4,"seed" to 17)
        stroke(a,"spray",args);stroke(b,"spray",args+mapOf("points" to List(10){listOf(8,8)}))
        val before=a.document.resolved(0,0)!!.pixels.count{it!=0};val after=b.document.resolved(0,0)!!.pixels.count{it!=0}
        assertTrue(before>1);assertTrue(after>before);assertTrue(after<144)
        b.undo();assertTrue(b.document.composite(0).all{it==0})
    }
    @Test fun softAirbrushBuildsOpacityAtRest() {
        val a=canvas();val b=canvas();val args=mapOf("size" to 9,"strength" to 20,"color" to 0xffff0000L)
        stroke(a,"airbrush",args);stroke(b,"airbrush",args+mapOf("points" to List(4){listOf(8,8)}))
        val p=a.document.resolved(0,0)!!.pixels
        assertEquals(51,p[136] ushr 24);assertTrue(p[132] ushr 24 in 1..50);assertEquals(0,p[68])
        assertTrue(b.document.resolved(0,0)!!.pixels[136] ushr 24>51)
    }
    @Test fun onePixelJumbleSwapsNativeIndexedNeighbours() {
        val e=canvas(8);e.document.frames[0].palette=intArrayOf(0,0xffff0000.toInt(),0xff0000ff.toInt())
        val c=e.document.editable(0,0);c.pixels.fill(1);c.pixels[136]=2;val before=c.pixels.sorted()
        stroke(e,"jumble",mapOf("strength" to 100,"seed" to 17))
        val p=e.document.resolved(0,0)!!.pixels;assertEquals(1,p[136]);assertEquals(before,p.sorted())
    }
    @Test fun blurSoftensIsolatedDetailWithoutDarkFringes() {
        val e=canvas();e.document.editable(0,0).pixels[136]=0xffffffff.toInt()
        stroke(e,"blur",mapOf("size" to 3,"strength" to 100))
        val p=e.document.resolved(0,0)!!.pixels;assertEquals(0x1cffffff,p[136]);assertEquals(0x1cffffff,p[135])
    }
}
