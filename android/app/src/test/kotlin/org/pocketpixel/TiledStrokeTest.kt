package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class TiledStrokeTest {
    private val palette=intArrayOf(0,0x80241c0b.toInt(),0x80654b16.toInt(),0x80ae852a.toInt(),
        0x80e0bd55.toInt(),0x80ffefae.toInt(),0xff1255ff.toInt())
    private val tools=listOf("pencil","eraser","line","rectangle","ellipse","fill","gradient",
        "spray","airbrush","blur","jumble","splatter")+paletteTextureTools
    private fun engine(width: Int,height: Int,depth: Int=32,pattern: Boolean=false): EditorEngine {
        val d=Document.create(width,height);d.depth=depth;d.frames[0].palette=palette.copyOf()
        if(pattern) {
            val c=d.editable(0,0)
            for(y in 0 until height) for(x in 0 until width) c.pixels[y*width+x]=if(depth==8) 1+(x+2*y)%6
                else d.drawingColor(0x80000000.toInt() or (((x*23)%256) shl 16) or (((y*31)%256) shl 8) or 47,0)
        }
        return EditorEngine().apply { replace(d) }
    }
    private fun args(extra: Map<String,Any?> = emptyMap())=mapOf<String,Any?>(
        "tool" to "pencil","points" to listOf(listOf(0,0)),"size" to 1,
        "color" to 0x80ae852aL,"wrap" to true
    )+extra

    @Test fun seamCrossingPreservesWorldDirectionAndDoesNotDrawAcrossTileInterior() {
        val e=engine(8,3)
        e.stroke(args(mapOf("points" to listOf(listOf(-1,1),listOf(1,1)))))
        val actual=e.document.composite(0)
        for(y in 0..2) for(x in 0..7) assertEquals(
            if(y==1 && x in setOf(7,0,1)) 0x80ae852a.toInt() else 0,actual[y*8+x])
    }

    @Test fun longWrappedStrokeAndOverlappingBrushFootprintsBlendOnceAndUndoOnce() {
        val e=engine(8,3);val before=Aseprite.write(e.document)
        e.stroke(args(mapOf("points" to listOf(listOf(7,1),listOf(17,1),listOf(-4,1)),"size" to 5)))
        assertTrue(e.document.composite(0).all { it==0x80ae852a.toInt() })
        e.undo();assertArrayEquals(before,Aseprite.write(e.document))
        assertEquals(false,e.state(false)["canUndo"])
    }

    @Test fun diagonalSymmetryCanonicalizesBeforeReflectionThenWrapsResults() {
        for(mask in 0..15) {
            val s=StrokeSymmetry(8,5,mask and 1 != 0,mask and 2 != 0,
                mask and 4 != 0,mask and 8 != 0,wrap=true)
            val expected=s.points(2,1)
            assertEquals(expected,s.points(-6,-4));assertEquals(expected,s.points(10,6))
            assertTrue(expected.size<=8)
            assertTrue(expected.all { (x,y) -> x in 0..7 && y in 0..4 })
        }
    }

    @Test fun periodicRepresentativeMatchesBruteForceNearestCoordinate() {
        for(period in 1..9) for(start in -9..9) for(end in start..start+18) for(coordinate in 0 until period) {
            val candidates=(start..end).filter { Math.floorMod(it,period)==coordinate }
            val actual=periodicRepresentative(start,end,coordinate,period)
            if(candidates.isEmpty()) assertNull(actual)
            else {
                assertTrue(actual in candidates)
                val distance=kotlin.math.abs(2*actual!!-start-end)
                assertTrue(candidates.all { kotlin.math.abs(2*it-start-end)>=distance })
            }
        }
    }

    @Test fun filledWrappedShapesMatchWorldRasterAndStayBoundedForExtremeDrags() {
        for(tool in listOf("rectangle","ellipse")) {
            for(box in listOf(intArrayOf(-2,-1,3,3),intArrayOf(-7,-4,12,9),intArrayOf(7,3,10,6))) {
                val (left,top,right,bottom)=box
                val w=(right-left+1).toLong();val h=(bottom-top+1).toLong();val expected=IntArray(40)
                for(y in top..bottom) for(x in left..right) {
                    val dx=2L*x-left-right;val dy=2L*y-top-bottom
                    if(tool=="rectangle" || dx*dx*h*h+dy*dy*w*w<=w*w*h*h)
                        expected[Math.floorMod(y,5)*8+Math.floorMod(x,8)]=0x80ae852a.toInt()
                }
                val e=engine(8,5)
                e.stroke(args(mapOf("tool" to tool,"filled" to true,"points" to listOf(listOf(left,top),listOf(right,bottom)))))
                assertArrayEquals(tool,expected,e.document.composite(0))
            }
            val e=engine(8,5)
            e.stroke(args(mapOf("tool" to tool,"filled" to true,"points" to listOf(listOf(-8192,-8192),listOf(8192,8192)))))
            assertTrue(e.document.composite(0).all { it==0x80ae852a.toInt() })
        }
    }

    @Test fun fillUsesToroidalAdjacencyWithoutLeakingIntoOtherColors() {
        val e=engine(8,3);val c=e.document.editable(0,0)
        c.pixels.fill(0xff00ff00.toInt());c.pixels[8]=0;c.pixels[15]=0
        e.stroke(args(mapOf("tool" to "fill","points" to listOf(listOf(-1,1)))))
        val p=e.document.composite(0)
        assertEquals(0x80ae852a.toInt(),p[8]);assertEquals(0x80ae852a.toInt(),p[15]);assertEquals(0xff00ff00.toInt(),p[9])
    }

    @Test fun blurAndJumbleUseOppositeEdgeNeighborsEvenOnOnePixelHighCanvas() {
        for(tool in listOf("blur","jumble")) {
            val e=engine(4,1);val c=e.document.editable(0,0)
            c.pixels.fill(0xff000000.toInt());c.pixels[3]=0xffffffff.toInt()
            e.stroke(args(mapOf("tool" to tool,"strength" to 100,"seed" to 1)))
            val p=e.document.composite(0)
            if(tool=="blur") assertEquals(0xff555555.toInt(),p[0])
            else assertArrayEquals(intArrayOf(0xffffffff.toInt(),0xff000000.toInt(),0xff000000.toInt(),0xff000000.toInt()),p)
        }
    }

    @Test fun retouchReadsWrappedDestinationOriginal() {
        val e=engine(8,3);e.document.frames[0].palette=intArrayOf(0,0xffff0000.toInt(),0xff0000ff.toInt())
        val c=e.document.editable(0,0);c.pixels[8]=0xffff0000.toInt();c.pixels[15]=0xff0000ff.toInt()
        e.stroke(args(mapOf("tool" to "ditherRetouch","points" to listOf(listOf(0,1)),"size" to 3)))
        val p=e.document.composite(0)
        assertEquals(0xffff0000.toInt(),p[8]);assertEquals(0xff0000ff.toInt(),p[15])
    }

    @Test fun allToolsRepeatIdenticallyWithPurePreviewAndSingleUndoOnNarrowTiles() {
        for(tool in tools) for((w,h) in listOf(8 to 5,1 to 1,1 to 7)) {
            val a=engine(w,h,pattern=true);val b=engine(w,h,pattern=true)
            val points=listOf(listOf(w-1,h-1),listOf(w+1,h+1),listOf(w+1,h+1))
            val p=args(mapOf("tool" to tool,"points" to points,"size" to 5,"seed" to 42,
                "strength" to 50,"density" to 12,"paletteIndex" to 3,"secondaryColor" to 0x20808080L,
                "gradient" to true,"filled" to true,"mirrorX" to true,"mirrorDiagonal" to true,"mirrorAntiDiagonal" to true))
            val before=Aseprite.write(a.document);val preview=a.previewStroke(p)
            assertArrayEquals(before,Aseprite.write(a.document));assertEquals(false,a.state(false)["canUndo"])
            a.stroke(p);b.stroke(p+mapOf("points" to points.map { listOf(it[0]-2*w,it[1]-h) }))
            assertArrayEquals("$tool $w/$h",a.document.composite(0),b.document.composite(0))
            assertArrayEquals(preview["pixels"] as ByteArray,a.state(false)["pixels"] as ByteArray)
            if(a.state(false)["canUndo"]==true) {
                val after=Aseprite.write(a.document);a.undo();assertArrayEquals(before,Aseprite.write(a.document))
                assertEquals(false,a.state(false)["canUndo"]);a.redo();assertArrayEquals(after,Aseprite.write(a.document))
            }
        }
    }

    @Test fun negativeCenterEllipsesHaveRepeatIndependentRounding() {
        val a=engine(5,9);val b=engine(5,9)
        a.stroke(args(mapOf("tool" to "ellipse","points" to listOf(listOf(-4,0),listOf(-2,3)))))
        b.stroke(args(mapOf("tool" to "ellipse","points" to listOf(listOf(1,9),listOf(3,12)))))
        assertArrayEquals(a.document.composite(0),b.document.composite(0))
    }

    @Test fun pureTextureFieldsAndSplatterSeedsRepeatPerTile() {
        val points=listOf(6 to 3,10 to 7,12 to 7);val shifted=points.map { (x,y) -> x-16 to y+5 }
        for(tool in paletteTextureTools) {
            fun raster(p: List<Pair<Int,Int>>) = paletteTexturePixels(tool,p,8,5,7,listOf(0,1,2,3,4),42,
                mirrorDiagonal=true,wrap=true)
            assertEquals(tool,raster(points),raster(shifted))
        }
        assertEquals(splatterPixels(points,8,5,7,42,mirrorDiagonal=true,wrap=true),
            splatterPixels(shifted,8,5,7,42,mirrorDiagonal=true,wrap=true))
    }

    @Test fun wrappedIndexedStrokePreservesSelectedFrameLayerAndExactIndex() {
        val e=engine(7,5,depth=8)
        e.edit(mapOf("action" to "addLayer","name" to "Wrapped"));e.edit(mapOf("action" to "addFrame"))
        val before=Aseprite.write(e.document)
        val p=args(mapOf("points" to listOf(listOf(-1,-1),listOf(1,1)),"paletteIndex" to 3))
        val preview=e.previewStroke(p);assertArrayEquals(before,Aseprite.write(e.document))
        e.stroke(p);assertArrayEquals(preview["pixels"] as ByteArray,e.state(false)["pixels"] as ByteArray)
        assertNull(e.document.resolved(0,0));assertNull(e.document.resolved(1,0))
        assertTrue(e.document.resolved(1,1)!!.pixels.all { it==0 || it==3 })
        e.undo();assertArrayEquals(before,Aseprite.write(e.document))
    }

    @Test fun normalViewStillClips() {
        val e=engine(8,3)
        e.stroke(args(mapOf("wrap" to false,"points" to listOf(listOf(-1,1),listOf(1,1)))))
        val p=e.document.composite(0)
        assertEquals(0,p[15]);assertEquals(0x80ae852a.toInt(),p[8]);assertEquals(0x80ae852a.toInt(),p[9])
    }
}
