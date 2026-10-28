package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class StrokeSymmetryTest {
    private val all = mapOf("mirrorX" to true, "mirrorY" to true,
        "mirrorDiagonal" to true, "mirrorAntiDiagonal" to true)
    private val palette = intArrayOf(0,0xff241c0b.toInt(),0xff654b16.toInt(),0xffae852a.toInt(),
        0xffe0bd55.toInt(),0xffffefae.toInt(),0xff1255ff.toInt())
    private fun engine(width: Int, height: Int) = EditorEngine().apply { replace(Document.create(width,height)) }
    private fun args(tool: String = "pencil", extra: Map<String,Any?> = emptyMap()) = mapOf<String,Any?>(
        "tool" to tool,"points" to listOf(listOf(3,3)),"size" to 1,"color" to 0x80ae852aL,
        "seed" to 42,"strength" to 57,"density" to 16
    ) + extra

    @Test fun exactCenteredDiagonalsClipRectanglesWithoutStretching() {
        assertEquals(setOf(4 to 1,2 to 3),StrokeSymmetry(6,4,mirrorDiagonal=true).points(4,1))
        assertEquals(setOf(4 to 1,3 to 0),StrokeSymmetry(6,4,mirrorAntiDiagonal=true).points(4,1))
        assertEquals(setOf(0 to 0),StrokeSymmetry(8,4,mirrorDiagonal=true).points(0,0))
        // 7x4 has a half-pixel center mismatch: ties snap toward top/left once.
        assertEquals(setOf(4 to 1,2 to 2),StrokeSymmetry(7,4,mirrorDiagonal=true).points(4,1))
        assertEquals(setOf(4 to 1,3 to 0),StrokeSymmetry(7,4,mirrorAntiDiagonal=true).points(4,1))
        assertEquals(setOf(3 to 2,2 to 3),StrokeSymmetry(5,5,mirrorDiagonal=true).points(3,2))
        assertEquals(setOf(3 to 2,2 to 3),StrokeSymmetry(6,6,mirrorDiagonal=true).points(3,2))
    }

    @Test fun inverseSourceBoundsContainEveryPixelThatCanReflectOntoCanvas() {
        assertEquals(SymmetryBounds(-2,0,6,8),StrokeSymmetry(5,9,mirrorDiagonal=true).sourceBounds)
        assertEquals(SymmetryBounds(0,-2,8,6),StrokeSymmetry(9,5,mirrorDiagonal=true).sourceBounds)
        assertEquals(SymmetryBounds(0,-2,6,5),StrokeSymmetry(7,4,mirrorDiagonal=true,mirrorAntiDiagonal=true).sourceBounds)
        for((width,height) in listOf(5 to 9,9 to 5,7 to 4,4 to 7,1 to 8)) for(mask in 0..15) {
            val symmetry=StrokeSymmetry(width,height,mask and 1 != 0,mask and 2 != 0,
                mask and 4 != 0,mask and 8 != 0)
            val bounds=symmetry.sourceBounds
            assertTrue(bounds.right-bounds.left+1 <= maxOf(width,height)+1)
            assertTrue(bounds.bottom-bounds.top+1 <= maxOf(width,height)+1)
            for(y in -10..18) for(x in -10..18) if(symmetry.points(x,y).isNotEmpty()) {
                assertTrue("$width/$height mask=$mask at $x,$y",x in bounds.left..bounds.right && y in bounds.top..bounds.bottom)
            }
        }
    }

    @Test fun offCanvasDabsReflectBeforeClippingOnRectangularCanvases() {
        for(tool in listOf("pencil","spray","airbrush","splatter")+paletteTextureTools) {
            val e=engine(5,9)
            e.document.frames[0].palette=palette.copyOf()
            e.document.editable(0,0).pixels[1*5+2]=0xff917344.toInt()
            val p=args(tool,mapOf("points" to listOf(listOf(-1,4)),"mirrorDiagonal" to true,
                "color" to 0xffae852aL,"paletteIndex" to 3))
            val before=Aseprite.write(e.document)
            val preview=e.previewStroke(p)
            e.stroke(p)
            assertArrayEquals(tool,preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
            assertNotEquals("$tool reflected dab",0xff917344.toInt(),e.document.composite(0)[1*5+2])
            e.undo();assertArrayEquals(tool,before,Aseprite.write(e.document))
        }
    }

    @Test fun fullyOffCanvasFilledShapesCanReflectOntoCanvas() {
        for(tool in listOf("rectangle","ellipse")) {
            val e=engine(5,9)
            val p=args(tool,mapOf("points" to listOf(listOf(-2,3),listOf(-1,5)),
                "filled" to true,"mirrorDiagonal" to true))
            val preview=e.previewStroke(p)
            e.stroke(p)
            assertArrayEquals(preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
            val pixels=e.document.composite(0)
            assertEquals(6,pixels.count { it != 0 })
            for(y in 0..1) for(x in 1..3) assertEquals(0x80ae852a.toInt(),pixels[y*5+x])
        }
    }

    @Test fun combinationsFormFiniteClosureAndDeduplicateAxes() {
        val counts=listOf(1,2,2,4,2,8,8,8,2,8,8,8,4,8,8,8)
        for(mask in 0..15) {
            val symmetry=StrokeSymmetry(9,9,mask and 1 != 0,mask and 2 != 0,
                mask and 4 != 0,mask and 8 != 0)
            assertEquals("mask=$mask",counts[mask],symmetry.transforms.size)
            assertEquals("center mask=$mask",setOf(4 to 4),symmetry.points(4,4))
        }
        assertEquals(setOf(6 to 5,2 to 5,6 to 3,2 to 3,5 to 6,3 to 6,5 to 2,3 to 2),
            StrokeSymmetry(9,9,true,true,true,true).points(6,5))
        assertEquals(setOf(6 to 5,5 to 6,3 to 2,2 to 3),
            StrokeSymmetry(9,9,mirrorDiagonal=true,mirrorAntiDiagonal=true).points(6,5))
        // No rounded intermediate reflection is fed to another transformation.
        assertEquals(setOf(4 to 1,2 to 2,3 to 0,2 to 2),
            StrokeSymmetry(7,4,mirrorDiagonal=true,mirrorAntiDiagonal=true).points(4,1))
    }

    @Test fun diagonalPencilUsesExpectedPixelsAndDoesNotAccumulateAlpha() {
        val e=engine(9,9)
        e.stroke(args(extra=all+mapOf("points" to listOf(listOf(6,5),listOf(6,5)))))
        val expected=setOf(6 to 5,2 to 5,6 to 3,2 to 3,5 to 6,3 to 6,5 to 2,3 to 2)
        val pixels=e.document.composite(0)
        for(y in 0..8) for(x in 0..8) assertEquals(if((x to y) in expected) 0x80ae852a.toInt() else 0,pixels[y*9+x])
        e.undo();assertTrue(e.document.composite(0).all { it==0 })
        assertEquals(false,e.state(false)["canUndo"])
        e.redo();assertArrayEquals(pixels,e.document.composite(0))
    }

    @Test fun fixedCenterDoesNotDuplicateAnyBrushDab() {
        for(tool in listOf("pencil","spray","airbrush","splatter")+paletteTextureTools) {
            val a=engine(7,7);val b=engine(7,7)
            for(e in listOf(a,b)) {
                e.document.frames[0].palette=intArrayOf(0x80ae852a.toInt())
                e.document.editable(0,0).pixels.fill(0x80444444.toInt())
            }
            val p=args(tool,mapOf("paletteIndex" to 0))
            a.stroke(p);b.stroke(p+all)
            assertArrayEquals(tool,a.document.composite(0),b.document.composite(0))
        }
    }

    @Test fun allToolsPreviewCommitAndUndoAgreeOnOddEvenRectangularCanvases() {
        val tools=listOf("pencil","eraser","line","rectangle","ellipse","fill","gradient",
            "spray","airbrush","splatter","blur","jumble")+paletteTextureTools
        for((width,height) in listOf(8 to 8,9 to 9,9 to 6,8 to 5)) for(tool in tools) {
            val e=engine(width,height)
            e.document.frames[0].palette=palette.copyOf()
            val c=e.document.editable(0,0)
            for(y in 0 until height) for(x in 0 until width) c.pixels[y*width+x]=
                0xff000000.toInt() or ((x*21) shl 16) or ((y*31) shl 8) or ((x+y)*11)
            val p=args(tool,all+mapOf("points" to listOf(listOf(width/3,height/3),listOf(width*2/3,height*2/3)),
                "size" to 3,"filled" to true,"paletteIndex" to 3,"color" to 0xffae852aL,
                "secondaryColor" to 0x80ffffffL))
            val before=Aseprite.write(e.document)
            val preview=e.previewStroke(p)
            assertArrayEquals("pure $tool $width/$height",before,Aseprite.write(e.document))
            assertEquals(false,e.state(false)["canUndo"])
            e.stroke(p)
            assertArrayEquals("preview $tool $width/$height",preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
            e.undo();assertArrayEquals("undo $tool $width/$height",before,Aseprite.write(e.document))
        }
    }

    @Test fun selectedFrameAndLayerArePreservedByDiagonalPreviewAndCommit() {
        val d=Document.create(7,5)
        d.addFrame(0,false)
        d.layers.add(Layer("Second"));d.frames.forEach { it.cels.add(null) }
        val e=EditorEngine().apply { replace(d);select(mapOf("frame" to 1,"layer" to 1)) }
        val before=Aseprite.write(e.document)
        val p=args(extra=all+mapOf("points" to listOf(listOf(4,2))))
        e.previewStroke(p)
        assertEquals(1,e.frame);assertEquals(1,e.layer)
        assertArrayEquals(before,Aseprite.write(e.document))
        e.stroke(p)
        assertEquals(1,e.frame);assertEquals(1,e.layer)
        assertTrue(e.document.composite(0).all { it==0 })
        assertNull(e.document.resolved(1,0))
        assertTrue(e.document.resolved(1,1)!!.pixels.any { it != 0 })
        e.undo();assertArrayEquals(before,Aseprite.write(e.document))
    }

    @Test fun fillGradientTransformsBothSeedAndGradientAxis() {
        for(anti in listOf(false,true)) {
            val e=engine(7,7);val c=e.document.editable(0,0)
            for(y in 0..6) for(x in 0..6) if(if(anti) x+y==6 else x==y) c.pixels[y*7+x]=0xff00ff00.toInt()
            e.stroke(args("fill",mapOf("points" to listOf(if(anti) listOf(0,1) else listOf(4,1)),
                "mirrorDiagonal" to !anti,"mirrorAntiDiagonal" to anti,"gradient" to true,
                "gradientDirection" to "horizontal","color" to 0xff000000L,"secondaryColor" to 0xffffffffL)))
            val p=e.document.composite(0)
            for(y in 0..6) for(x in 0..6) {
                val target=if(anti) (6-x)*7+6-y else x*7+y
                assertEquals("anti=$anti at $x,$y",p[y*7+x],p[target])
            }
        }
    }

    @Test fun ditherToolsReadOriginalPixelsInMirroredDestinationSpace() {
        for(tool in listOf("ditherPaint","ditherRetouch")) {
            val d=Document.create(9,9);d.frames[0].palette=palette.copyOf()
            val c=d.editable(0,0);c.pixels[2*9+6]=0xffba7a24.toInt();c.pixels[6*9+2]=0xff3459ba.toInt()
            val direct=EditorEngine().apply { replace(d.copyDeep()) }
            val mirrored=EditorEngine().apply { replace(d.copyDeep()) }
            direct.stroke(args(tool,mapOf("points" to listOf(listOf(2,6)),"paletteIndex" to 3,"color" to 0xffae852aL)))
            mirrored.stroke(args(tool,mapOf("points" to listOf(listOf(6,2)),"paletteIndex" to 3,
                "color" to 0xffae852aL,"mirrorDiagonal" to true)))
            assertEquals(tool,direct.document.composite(0)[6*9+2],mirrored.document.composite(0)[6*9+2])
        }
    }

    @Test fun directionalTexturePixelsAreReflectedRatherThanRepaintedWithUnreflectedDirection() {
        for(tool in paletteTextureTools-listOf("ditherPaint","ditherRetouch")) for(reverse in listOf(false,true)) {
            val path=listOf(2 to 8,4 to 12).let { if(reverse) it.reversed() else it }
            val plain=paletteTexturePixels(tool,path,16,16,3,listOf(0,1,2,3,4),42)
            val mirrored=paletteTexturePixels(tool,path,16,16,3,listOf(0,1,2,3,4),42,mirrorDiagonal=true)
            assertTrue(plain.isNotEmpty())
            for((key,shade) in plain) {
                val x=key%16;val y=key/16
                assertEquals("$tool reversed=$reverse at $x,$y",shade,mirrored[x*16+y])
            }
        }
    }

    @Test fun overlappingLeavesStayStableWithMixedParityDiagonalRasterization() {
        val path=listOf(4 to 3,12 to 3,12 to 8,5 to 8)
        fun raster(p: List<Pair<Int,Int>>) = paletteTexturePixels("leaves",p,18,13,9,
            listOf(0,1,2,3,4),42,true,true,true,true)
        val full=raster(path)
        assertEquals(full,raster(path.reversed()))
        for((key,value) in raster(path.take(3))) assertEquals(value,full[key])
    }
    @Test fun negativeHalfPixelEllipseOutlinesDoNotGainStrayReflectedPixels() {
        for((width,height,points) in listOf(
            Triple(5,9,listOf(listOf(-4,0),listOf(-2,3))),
            Triple(9,5,listOf(listOf(-2,-2),listOf(1,0)))
        )) for(reverse in listOf(false,true)) {
            val e=engine(width,height)
            val p=args("ellipse",mapOf("points" to if(reverse) points.reversed() else points,
                "mirrorDiagonal" to true,"color" to 0x80ff0000L))
            val preview=e.previewStroke(p)
            e.stroke(p)
            val expected=IntArray(width*height).apply { this[0]=0x80ff0000.toInt() }
            assertArrayEquals(expected,e.document.composite(0))
            assertArrayEquals(preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
            e.undo();assertTrue(e.document.composite(0).all { it==0 })
        }
    }

}
