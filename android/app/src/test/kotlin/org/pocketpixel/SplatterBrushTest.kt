package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class SplatterBrushTest {
    private fun canvas(depth: Int = 32): EditorEngine = EditorEngine().apply {
        replace(Document.create(64,64).apply { this.depth = depth })
    }
    private fun args(): Map<String,Any?> = mapOf("tool" to "splatter",
        "points" to listOf(listOf(10,12),listOf(46,36),listOf(46,36),listOf(20,48)),
        "size" to 24,"seed" to 421,"color" to 0x80c86432L)
    private fun raster(points: List<Pair<Int,Int>>, seed: Long = 421, size: Int = 24) =
        splatterPixels(points,64,64,size,seed)

    @Test fun seededSparseDropletsDoNotAccumulateWhileHeld() {
        val p = raster(listOf(32 to 32))
        assertEquals(p,raster(listOf(32 to 32)))
        assertEquals(p,raster(List(20) {32 to 32}))
        assertNotEquals(p,raster(listOf(32 to 32),422))
        assertTrue(p.size > 10); assertTrue(p.size < 24*24/2)
        assertTrue(p.values.toSet().size > 2)
        assertTrue(p.values.all {it in 64..255})
        assertTrue(p.entries.any {p[it.key+1] == it.value})
        assertEquals(setOf(4*64+3),raster(listOf(3 to 4),size=1).keys)
    }
    @Test fun pointerSegmentationDoesNotChangeSpacing() {
        assertEquals(raster(listOf(8 to 8,56 to 32)),
            raster(listOf(8 to 8,20 to 14,20 to 14,32 to 20,56 to 32)))
        val prefix = raster(listOf(8 to 8,32 to 20))
        val full = raster(listOf(8 to 8,32 to 20,56 to 32))
        assertTrue(prefix.entries.all {(full[it.key] ?: 0) >= it.value})
    }
    @Test fun previewMirrorsModesAndHistory() {
        for (depth in listOf(8,16,32)) {
            val e = canvas(depth)
            e.document.frames[0].palette = intArrayOf(0,0x80c86432.toInt(),0x80c86432.toInt())
            val before = Aseprite.write(e.document)
            val args = args()+mapOf("paletteIndex" to 2,"mirrorX" to true,"mirrorY" to true)
            val preview = e.previewStroke(args)
            assertArrayEquals(before,Aseprite.write(e.document))
            assertEquals(false,e.state(false)["canUndo"]); assertFalse(e.dirty)
            e.stroke(args)
            assertArrayEquals(preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
            val pixels = e.document.resolved(0,0)!!.pixels
            val painted = pixels.filter {it != 0}
            assertTrue(painted.isNotEmpty())
            if (depth == 8) {
                assertEquals(setOf(2),painted.toSet())
                assertArrayEquals(intArrayOf(0,0x80c86432.toInt(),0x80c86432.toInt()),e.document.frames[0].palette)
            } else {
                assertTrue(painted.all {it ushr 24 in 1..128})
                assertTrue(painted.map {it ushr 24}.toSet().size > 2)
                if (depth == 32) assertTrue(painted.all {it and 0xffffff == 0xc86432})
                else assertTrue(painted.all {it and 255 == (it ushr 8 and 255)})
            }
            for (y in 0 until 64) for (x in 0 until 64) {
                assertEquals(pixels[y*64+x],pixels[y*64+63-x])
                assertEquals(pixels[y*64+x],pixels[(63-y)*64+x])
            }
            val after = Aseprite.write(e.document)
            e.undo(); assertArrayEquals(before,Aseprite.write(e.document)); assertEquals(false,e.state(false)["canUndo"])
            e.redo(); assertArrayEquals(after,Aseprite.write(e.document))
        }
    }
    @Test fun sourceOverBlendsOnlyOncePerPixel() {
        val e = canvas(); val background = 0x600020d0; val color = 0x80c86432.toInt()
        e.document.editable(0,0).pixels.fill(background)
        e.stroke(args())
        val mask = raster(listOf(10 to 12,46 to 36,46 to 36,20 to 48))
        val actual = e.document.resolved(0,0)!!.pixels
        for (i in actual.indices) {
            val alpha = mask[i]?.let {(128*it+127)/255} ?: 0
            assertEquals(over(background,(color and 0xffffff) or (alpha shl 24)),actual[i])
        }
    }
    @Test fun zeroAlphaOffCanvasAndTransparentIndicesAreNoOps() {
        for (depth in listOf(8,16,32)) {
            val e = canvas(depth)
            e.document.frames[0].palette = intArrayOf(0,0x80c86432.toInt(),0x00c86432)
            val before = Aseprite.write(e.document)
            e.stroke(args()+mapOf("color" to 0x00c86432,"paletteIndex" to 1))
            assertArrayEquals(before,Aseprite.write(e.document)); assertEquals(false,e.state(false)["canUndo"]); assertFalse(e.dirty)
            e.stroke(args()+mapOf("points" to listOf(listOf(-100,-100),listOf(-80,-80))))
            assertArrayEquals(before,Aseprite.write(e.document)); assertEquals(false,e.state(false)["canUndo"])
            if (depth == 8) for (index in listOf(0,2)) {
                e.stroke(args()+mapOf("paletteIndex" to index))
                assertArrayEquals(before,Aseprite.write(e.document)); assertEquals(false,e.state(false)["canUndo"])
            }
        }
    }
    @Test fun onlySelectedFrameAndLayerChange() {
        val e = canvas()
        e.edit(mapOf("action" to "addLayer","name" to "Paint"))
        e.edit(mapOf("action" to "addFrame"))
        e.stroke(args())
        assertTrue(e.document.frames[0].cels.all {it == null})
        assertNull(e.document.frames[1].cels[0]); assertNotNull(e.document.frames[1].cels[1])
        val before = Aseprite.write(e.document)
        e.document.layers[1].flags = e.document.layers[1].flags and 2.inv()
        assertThrows(IllegalArgumentException::class.java) { e.stroke(args()) }
        e.document.layers[1].flags = e.document.layers[1].flags or 2
        assertArrayEquals(before,Aseprite.write(e.document))
    }
}
