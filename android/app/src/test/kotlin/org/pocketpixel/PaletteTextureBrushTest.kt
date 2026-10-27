package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class PaletteTextureBrushTest {
    private val tools = listOf("metal", "cluster", "stripes", "sphere", "knife")
    private val palette = intArrayOf(0, 0xff241c0b.toInt(), 0xff654b16.toInt(), 0xffae852a.toInt(), 0xffe0bd55.toInt(), 0xffffefae.toInt(), 0xff1255ff.toInt())
    private fun canvas(depth: Int = 32): EditorEngine {
        val d = Document.create(32, 32)
        d.depth = depth
        d.frames[0].palette = palette.copyOf()
        return EditorEngine().apply { replace(d) }
    }
    private fun args(tool: String, extra: Map<String, Any?> = emptyMap()) = mapOf(
        "tool" to tool, "points" to listOf(listOf(7, 16), listOf(24, 16)),
        "size" to 9, "color" to 0xffae852aL, "paletteIndex" to 3, "seed" to 17
    ) + extra

    @Test fun emptyTextureDoesNotCreateUndo() {
        for (tool in tools) {
            val e = canvas()
            e.document.frames[0].palette = intArrayOf(0)
            e.stroke(args(tool, mapOf("paletteIndex" to 0)))
            assertEquals(false, e.state(false)["canUndo"])
            val outside = canvas()
            outside.stroke(args(tool, mapOf("points" to listOf(listOf(-100,-100)))))
            assertEquals(false, outside.state(false)["canUndo"])
        }
    }

    @Test fun everyBrushUsesPaletteAndHasOneUndo() {
        for (tool in tools) {
            val e = canvas()
            val before = Aseprite.write(e.document)
            e.stroke(args(tool))
            val pixels = e.document.composite(0)
            assertTrue(tool, pixels.any { it != 0 })
            assertTrue(tool, pixels.all { it == 0 || it in palette })
            val after = Aseprite.write(e.document)
            e.undo()
            assertArrayEquals(tool, before, Aseprite.write(e.document))
            assertEquals(tool, false, e.state(false)["canUndo"])
            e.redo()
            assertArrayEquals(tool, after, Aseprite.write(e.document))
        }
    }

    @Test fun previewIsPureAndMatchesCommit() {
        for (tool in tools) {
            val e = canvas()
            val before = Aseprite.write(e.document)
            val preview = e.previewStroke(args(tool))
            assertArrayEquals(before, Aseprite.write(e.document))
            assertEquals(false, e.state(false)["canUndo"])
            e.stroke(args(tool))
            assertArrayEquals(tool, preview["pixels"] as ByteArray, e.state(false)["pixels"] as ByteArray)
        }
    }

    @Test fun indexedPaintingStoresOnlyValidIndicesAndPreservesPalette() {
        for (tool in tools) {
            val e = canvas(8)
            e.stroke(args(tool, mapOf("mirrorX" to true, "mirrorY" to true)))
            assertArrayEquals(palette, e.document.frames[0].palette)
            assertTrue(e.document.resolved(0, 0)!!.pixels.all { it in palette.indices })
            assertTrue(e.document.resolved(0, 0)!!.pixels.any { it > 0 })
        }
    }

    @Test fun repeatedStationaryEventsDoNotChangeTexture() {
        for (tool in tools) {
            val a = canvas(); val b = canvas()
            a.stroke(args(tool, mapOf("points" to listOf(listOf(16, 16)))))
            b.stroke(args(tool, mapOf("points" to List(20) { listOf(16, 16) })))
            assertArrayEquals(tool, a.document.composite(0), b.document.composite(0))
        }
    }

    @Test fun aSinglePaletteShadeIsUsable() {
        for (tool in tools) {
            val e = canvas()
            e.document.frames[0].palette = intArrayOf(0xffae852a.toInt())
            e.stroke(args(tool, mapOf("paletteIndex" to 0)))
            assertTrue(e.document.composite(0).all { it == 0 || it == 0xffae852a.toInt() })
            assertTrue(e.document.composite(0).any { it != 0 })
        }
    }
    @Test fun translucentTextureBlendsOnlyOnceAndGrayscaleConvertsAfterBlend() {
        for (depth in listOf(16, 32)) for (tool in tools) {
            val e = canvas(depth)
            val ink = 0x80ae852a.toInt()
            val background = 0x80444444.toInt()
            e.document.frames[0].palette = intArrayOf(ink)
            e.document.editable(0, 0).pixels.fill(background)
            val expected = e.document.drawingColor(over(background, ink), 0)
            e.stroke(args(tool, mapOf("paletteIndex" to 0, "color" to ink.toLong(),
                "points" to listOf(listOf(7,16), listOf(24,16), listOf(7,16)))))
            val pixels = e.document.resolved(0,0)!!.pixels
            assertEquals("$tool/$depth", expected, pixels[16*32+16])
            assertTrue("$tool/$depth", pixels.all { it == background || it == expected })
        }
    }

    @Test fun ditherPaintUsesExistingPaletteAndOriginalBackground() {
        val a = canvas(); val b = canvas()
        for(e in listOf(a,b)) e.document.editable(0,0).pixels.fill(palette[1])
        val p = args("ditherPaint", mapOf("strength" to 50))
        a.stroke(p)
        b.stroke(p + mapOf("points" to listOf(listOf(7,16),listOf(12,16),listOf(24,16),listOf(24,16))))
        assertArrayEquals(a.document.composite(0),b.document.composite(0))
        assertTrue(a.document.composite(0).all { it in palette })
    }

    @Test fun retouchPreservesTransparencyAndUnsupportedAlpha() {
        val e=canvas()
        val cel=e.document.editable(0,0)
        cel.pixels[16*32+16]=0x80123456.toInt()
        e.stroke(args("ditherRetouch", mapOf("points" to listOf(listOf(16,16)))))
        assertEquals(0x80123456.toInt(),e.document.resolved(0,0)!!.pixels[16*32+16])
        assertEquals(1,e.document.composite(0).count { it!=0 })
    }

    @Test fun retouchLeavesExactPalettePixelsAndDuplicateIndicesUntouched() {
        val e=canvas(8)
        e.document.frames[0].palette=palette + intArrayOf(palette[3])
        e.document.editable(0,0).pixels.fill(palette.size)
        e.stroke(args("ditherRetouch"))
        // Matching colors are not changed; selected duplicate indices should stay.
        assertTrue(e.document.resolved(0,0)!!.pixels.all { it==palette.size })
    }

    @Test fun paletteRampKeepsRequestedDuplicateAndRejectsUnrelatedBlue() {
        val p=palette+intArrayOf(palette[3])
        val ramp=paletteShadeRamp(p,palette[3],p.lastIndex,0)
        assertEquals(p.lastIndex,ramp[2])
        assertFalse(ramp.contains(6))
        assertTrue(ramp.all { it>0 })
    }

    @Test fun knifeReversesLightSideAndSphereDoesNot() {
        fun pixelMap(tool:String,points:List<Pair<Int,Int>>) = paletteTexturePixels(tool,points,32,32,9,listOf(0,1,2,3,4))
        val east=listOf(7 to 16,24 to 16);val west=east.reversed()
        val ke=pixelMap("knife",east);val kw=pixelMap("knife",west)
        assertTrue(ke[14*32+16]!!>ke[18*32+16]!!)
        assertTrue(kw[14*32+16]!!<kw[18*32+16]!!)
        val se=pixelMap("sphere",east);val sw=pixelMap("sphere",west)
        assertTrue(se[14*32+16]!!>se[18*32+16]!!)
        assertTrue(sw[14*32+16]!!>sw[18*32+16]!!)
    }

}
