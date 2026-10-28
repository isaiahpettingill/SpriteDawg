package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class PaletteTextureBrushTest {
    private val tools = listOf("metal", "cluster", "stripes", "sphere", "knife", "bark", "leaves")
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

    @Test fun noOpRetouchPreservesRedoDirtyAndLinkedCel() {
        for (source in listOf(palette[3], 0x80123456.toInt(), 0)) {
            val e = canvas()
            e.document.editable(0,0).pixels.fill(source)
            e.document.addFrame(0, false)
            e.document.frames[1].cels[0] = Cel(0,0,0,0,intArrayOf(),link=0)
            e.select(mapOf("frame" to 1))
            e.stroke(args("pencil"))
            e.undo(); e.saved()
            assertEquals(true, e.state(false)["canRedo"])
            val before = Aseprite.write(e.document)
            e.stroke(args("ditherRetouch"))
            assertArrayEquals(before, Aseprite.write(e.document))
            assertFalse(e.dirty)
            assertEquals(true, e.state(false)["canRedo"])
            assertEquals(0, e.document.frames[1].cels[0]!!.link)
        }
    }

    @Test fun indexedTransparentTextureSelectionIsNoOp() {
        for (tool in tools) {
            val e = canvas(8)
            e.document.frames[0].palette[0] = 0xffff00ff.toInt()
            val before = Aseprite.write(e.document)
            e.stroke(args(tool, mapOf("paletteIndex" to 0, "color" to 0xffff00ffL)))
            assertArrayEquals(before, Aseprite.write(e.document))
            assertFalse(e.dirty)
            assertEquals(false,e.state(false)["canUndo"])
        }
    }

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

    @Test fun barkIsStableAcrossRevisitsAndPreviewExtensions() {
        fun raster(points: List<Pair<Int,Int>>, seed: Long = 421L) =
            paletteTexturePixels("bark", points, 96, 96, 24, listOf(0,1,2,3,4), seed)
        val first = raster(listOf(16 to 24, 64 to 24))
        val extended = raster(listOf(16 to 24, 64 to 24, 64 to 64, 16 to 64, 16 to 24))
        assertEquals(first, raster(listOf(16 to 24, 16 to 24, 32 to 24, 48 to 24, 64 to 24)))
        assertEquals(first, raster(listOf(64 to 24, 16 to 24)))
        for ((pixel, shade) in first) assertEquals("Extended preview must not repaint prior grain", shade, extended[pixel])
        assertNotEquals(first, raster(listOf(16 to 24, 64 to 24), 422L))
    }

    @Test fun barkHasLongitudinalIrregularGrainRatherThanSpecklesOrStripes() {
        val points = listOf(16 to 16, 80 to 16, 80 to 40, 16 to 40,
            16 to 64, 80 to 64, 80 to 80, 16 to 80)
        val pixels = paletteTexturePixels("bark", points, 96, 96, 32, listOf(0,1,2,3,4), 421L)
        var horizontalChanges = 0; var verticalChanges = 0
        for (y in 16 until 79) for (x in 16 until 79) {
            val shade = pixels[y*96+x]
            assertNotNull(shade)
            if (shade != pixels[y*96+x+1]) horizontalChanges++
            if (shade != pixels[(y+1)*96+x]) verticalChanges++
        }
        assertEquals(setOf(0,1,2,3,4), pixels.values.toSet())
        assertTrue("Furrows should vary along their length", verticalChanges > 0)
        assertTrue("Grain should run vertically, not speckle", verticalChanges * 2 < horizontalChanges)
        assertNotEquals(pixels, paletteTexturePixels("stripes", points, 96, 96, 32, listOf(0,1,2,3,4), 421L))
    }

    @Test fun barkIncludesSeededElongatedKnotWithDarkCoreAndLitRim() {
        val pixels = paletteTexturePixels("bark", listOf(61 to 62), 96, 96, 32, listOf(0,1,2,3,4), 17L)
        // This seed places a knot at (61.056, 62.272). Probe its core, wall,
        // lit inner rim and dark outer ring in both axes, not just coverage.
        assertEquals(0, pixels[62*96+61])
        assertEquals(1, pixels[62*96+63])
        assertEquals(3, pixels[62*96+64])
        assertEquals(0, pixels[62*96+57])
        assertEquals(1, pixels[69*96+61])
        assertEquals(3, pixels[72*96+61])
        assertEquals(0, pixels[75*96+61])
    }

    @Test fun leavesAreStableAcrossRevisitsAndPreviewExtensions() {
        fun raster(points: List<Pair<Int,Int>>, seed: Long = 421L) =
            paletteTexturePixels("leaves", points, 96, 96, 24, listOf(0,1,2,3,4), seed)
        val first = raster(listOf(16 to 24, 64 to 24))
        val extended = raster(listOf(16 to 24, 64 to 24, 64 to 64, 16 to 64, 16 to 24))
        assertEquals(first, raster(listOf(16 to 24, 16 to 24, 32 to 24, 48 to 24, 64 to 24)))
        assertEquals(first, raster(listOf(64 to 24, 16 to 24)))
        for ((pixel, shade) in first) assertEquals("Preview must not repaint earlier leaves", shade, extended[pixel])
        assertNotEquals(first, raster(listOf(16 to 24, 64 to 24), 422L))
        assertEquals(setOf(0,1,2,3,4), first.values.toSet())
    }

    @Test fun leavesHaveCoherentDarkInteriorsAndLitRims() {
        val points = (0..96 step 16).flatMap { y ->
            if (y % 32 == 0) listOf(0 to y, 95 to y) else listOf(95 to y, 0 to y)
        }
        val pixels = paletteTexturePixels("leaves", points, 96, 96, 32, listOf(0,1,2,3,4), 421L)
        assertNotEquals(pixels, paletteTexturePixels("cluster", points, 96, 96, 32, listOf(0,1,2,3,4), 421L))
        var coherent = 0; var litRims = 0
        for (y in 8 until 88) for (x in 8 until 88) {
            val shade = pixels[y*96+x]!!; val right = pixels[y*96+x+1]!!
            if (shade == right) coherent++
            if (shade <= 2 && right >= 3) litRims++
        }
        assertTrue(coherent > 3000)
        assertTrue(litRims > 100)
    }

}
