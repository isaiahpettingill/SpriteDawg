package org.pocketpixel
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
class BrushInteropTest {
@Test fun nativeBrushesMatchDartExactRgba() {
    val path=System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to the Dart brush fixture directory",path!=null)
    val out=File(path!!)
    fun run(name:String,pattern:Boolean,args:Map<String,Any?>,barrier:Boolean=false) {
        val d=Document.create(32,32);val c=d.editable(0,0)
        if(pattern) for(y in 0..31) for(x in 0..31)c.pixels[y*32+x]=(((x*17+y*13)%256) shl 24) or (((x*7)%256) shl 16) or (((y*9)%256) shl 8) or (((x+y)*5)%256)
        if(barrier)for(y in 0..31)c.pixels[y*32+16]=0xff00ff00.toInt()
        val e=EditorEngine();e.replace(d);e.stroke(args)
        assertArrayEquals(name,File(out,"$name.rgba").readBytes(),e.state(false)["pixels"] as ByteArray)
    }
    run("gradient",false,mapOf("tool" to "fill","points" to listOf(listOf(2,3)),"gradient" to true,"gradientDirection" to "horizontal","color" to 0xffc86432L,"secondaryColor" to 0x10010203L,"mirrorX" to true),true)
    run("linear-gradient",true,mapOf("tool" to "gradient","points" to listOf(listOf(-8192,-8192),listOf(8192,8192)),"color" to 0x80ff0000L,"secondaryColor" to 0x200000ffL,"mirrorX" to true,"size" to 32))
    run("spray",false,mapOf("tool" to "spray","points" to listOf(listOf(4,5),listOf(18,19),listOf(20,19)),"size" to 8,"density" to 70,"seed" to 42,"mirrorX" to true,"mirrorY" to true,"color" to 0x80c86432L))
    run("airbrush",true,mapOf("tool" to "airbrush","points" to listOf(listOf(5,5),listOf(5,5),listOf(13,15)),"size" to 9,"strength" to 20,"color" to 0x80c86432L,"mirrorX" to true,"mirrorY" to true))
    run("alpha",true,mapOf("tool" to "pencil","points" to listOf(listOf(5,5),listOf(13,15),listOf(5,5)),"size" to 5,"color" to 0x80c86432L,"mirrorX" to true))
    run("blur",true,mapOf("tool" to "blur","points" to listOf(listOf(8,8),listOf(20,12)),"size" to 5,"strength" to 67,"mirrorX" to true,"mirrorY" to true))
    run("jumble",true,mapOf("tool" to "jumble","points" to listOf(listOf(10,10),listOf(16,17)),"size" to 8,"strength" to 70,"seed" to 99,"mirrorX" to true))
    run("ellipse",false,mapOf("tool" to "ellipse","points" to listOf(listOf(18,22),listOf(3,5)),"filled" to true,"color" to 0x80c86432L,"mirrorX" to true))
}

@Test fun paletteTexturesMatchDartExactRgba() {
    val path = System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to the Dart brush fixture directory", path != null)
    val out = File(path!!)
    val gold = intArrayOf(0,0xff241c0b.toInt(),0xff654b16.toInt(),0xffae852a.toInt(),0xffe0bd55.toInt(),0xffffefae.toInt(),0xff1255ff.toInt())
    val alpha = intArrayOf(0,0x80241c0b.toInt(),0x80654b16.toInt(),0x80ae852a.toInt(),0x80e0bd55.toInt(),0x80ffefae.toInt(),0xff1255ff.toInt())
    for (tool in paletteTextureTools) for (mode in listOf("", "indexed-", "alpha-")) {
        val d = Document.create(32,32)
        d.depth = if (mode == "indexed-") 8 else 32
        d.frames[0].palette = (if (mode == "alpha-") alpha else gold).copyOf()
        val c = d.editable(0,0)
        if (mode == "indexed-") c.pixels.fill(2)
        else if (mode == "alpha-") c.pixels.fill(0x80a5802c.toInt())
        else if (tool == "ditherRetouch") c.pixels.fill(0xffa5802c.toInt())
        else for(y in 0..31) for(x in 0..31) c.pixels[y*32+x] = (((x*17+y*13)%256) shl 24) or (((x*7)%256) shl 16) or (((y*9)%256) shl 8) or (((x+y)*5)%256)
        val e = EditorEngine(); e.replace(d)
        e.stroke(mapOf("tool" to tool, "points" to listOf(listOf(4,5),listOf(18,19),listOf(20,19)),
            "size" to 9, "seed" to 42, "strength" to 50,
            "color" to if (mode == "alpha-") 0x80ae852aL else 0xffae852aL,
            "paletteIndex" to 3, "mirrorX" to true, "mirrorY" to true))
        val name = "texture-$mode$tool"
        assertArrayEquals(name, File(out,"$name.rgba").readBytes(), e.state(false)["pixels"] as ByteArray)
    }
}

@Test fun splatterMatchesDartExactRgbaAndIndexedAlpha() {
    val path = System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to Dart fixtures", path != null)
    for (indexed in listOf(false, true)) {
        val d = Document.create(32,32)
        if (indexed) {
            d.depth = 8
            d.frames[0].palette = intArrayOf(0, 0x80c86432.toInt(), 0x80c86432.toInt())
        } else {
            val c = d.editable(0,0)
            for (y in 0..31) for (x in 0..31) c.pixels[y*32+x] = (((x*17+y*13)%256) shl 24) or (((x*7)%256) shl 16) or (((y*9)%256) shl 8) or (((x+y)*5)%256)
        }
        val e = EditorEngine(); e.replace(d)
        val args = mutableMapOf<String,Any?>("tool" to "splatter",
            "points" to listOf(listOf(-3,5),listOf(18,19),listOf(18,19),listOf(20,19)),
            "size" to 20, "seed" to 42, "mirrorX" to true, "mirrorY" to true, "color" to 0x80c86432L)
        if (indexed) args["paletteIndex"] = 2
        e.stroke(args)
        val name = if (indexed) "splatter-indexed" else "splatter"
        assertArrayEquals(name, File(path!!,"$name.rgba").readBytes(), e.state(false)["pixels"] as ByteArray)
        if (indexed) org.junit.Assert.assertTrue(e.document.resolved(0,0)!!.pixels.all { it == 0 || it == 2 })
    }
}

@Test fun diagonalSymmetryMatchesDartOnSquareAndRectangularCanvases() {
    val path=System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to Dart fixtures",path != null)
    val out=File(path!!)
    val palette=intArrayOf(0,0x80241c0b.toInt(),0x80654b16.toInt(),0x80ae852a.toInt(),
        0x80e0bd55.toInt(),0x80ffefae.toInt(),0xff1255ff.toInt())
    val tools=listOf("pencil","eraser","line","rectangle","ellipse","fill","gradient",
        "spray","airbrush","blur","jumble","splatter")+paletteTextureTools
    for((width,height) in listOf(9 to 9,10 to 10,11 to 7,10 to 7)) for(depth in listOf(8,16,32)) for(tool in tools) {
        val d=Document.create(width,height);d.depth=depth;d.frames[0].palette=palette.copyOf()
        val c=d.editable(0,0)
        for(y in 0 until height) for(x in 0 until width) c.pixels[y*width+x]=if(depth==8) 1+(x+2*y)%6
            else d.drawingColor((((x*17+y*13)%256) shl 24) or (((x*7)%256) shl 16) or
                (((y*9)%256) shl 8) or (((x+y)*5)%256),0)
        val e=EditorEngine().apply { replace(d) }
        e.stroke(mapOf("tool" to tool,"points" to listOf(if(tool=="fill") listOf(1,2) else listOf(-2,1),listOf(width-3,height-3),
            listOf(width-3,height-3),listOf(2,height-2)),"size" to 5,"seed" to 42,"density" to 12,
            "strength" to 50,"color" to 0x80ae852aL,"paletteIndex" to 3,"filled" to true,
            "gradient" to true,"gradientDirection" to "horizontal","secondaryColor" to 0x20808080L,
            "mirrorDiagonal" to true,"mirrorAntiDiagonal" to (height%2!=0),
            "mirrorX" to (width%2==0),"mirrorY" to (depth==16)))
        val name="symmetry-${width}x${height}-$depth-$tool"
        assertArrayEquals(name,File(out,"$name.rgba").readBytes(),e.state(false)["pixels"] as ByteArray)
    }
}

@Test fun negativeCenterEllipseOutlinesMatchDartInBothDragDirections() {
    val path=System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to Dart fixtures",path != null)
    for((width,height,points) in listOf(
        Triple(5,9,listOf(listOf(-4,0),listOf(-2,3))),
        Triple(9,5,listOf(listOf(-2,-2),listOf(1,0)))
    )) for(reverse in listOf(false,true)) {
        val e=EditorEngine().apply { replace(Document.create(width,height)) }
        e.stroke(mapOf("tool" to "ellipse","points" to if(reverse) points.reversed() else points,
            "size" to 1,"color" to 0x80ff0000L,"mirrorDiagonal" to true))
        val name="negative-outline-${width}x${height}-$reverse"
        assertArrayEquals(name,File(path!!,"$name.rgba").readBytes(),e.state(false)["pixels"] as ByteArray)
    }
}

@Test fun wrappedToolsMatchDartIncludingNarrowAndMixedParityTiles() {
    val path=System.getenv("SPRITEDAWG_BRUSH_INTEROP_DIR")
    assumeTrue("Set SPRITEDAWG_BRUSH_INTEROP_DIR to Dart fixtures",path != null)
    val out=File(path!!)
    val palette=intArrayOf(0,0x80241c0b.toInt(),0x80654b16.toInt(),0x80ae852a.toInt(),
        0x80e0bd55.toInt(),0x80ffefae.toInt(),0xff1255ff.toInt())
    val tools=listOf("pencil","eraser","line","rectangle","ellipse","fill","gradient",
        "spray","airbrush","blur","jumble","splatter")+paletteTextureTools
    for((width,height) in listOf(8 to 5,7 to 7,1 to 1,1 to 7)) for(depth in listOf(8,16,32)) for(tool in tools) {
        val d=Document.create(width,height);d.depth=depth;d.frames[0].palette=palette.copyOf()
        val c=d.editable(0,0)
        for(y in 0 until height) for(x in 0 until width) c.pixels[y*width+x]=if(depth==8) 1+(x+2*y)%6
            else d.drawingColor(0x80000000.toInt() or (((x*23)%256) shl 16) or (((y*31)%256) shl 8) or 47,0)
        val e=EditorEngine().apply { replace(d) }
        e.stroke(mapOf("tool" to tool,"wrap" to true,"points" to listOf(listOf(-1,-1),listOf(1,1),
            listOf(width+1,1),listOf(width+1,1)),"size" to 5,"seed" to 42,"density" to 12,
            "strength" to 50,"color" to 0x80ae852aL,"paletteIndex" to 3,"filled" to (depth!=16),
            "gradient" to true,"gradientDirection" to "horizontal","secondaryColor" to 0x20808080L,
            "mirrorDiagonal" to true,"mirrorAntiDiagonal" to (height%2!=0),
            "mirrorX" to (width%2==0),"mirrorY" to (depth==16)))
        val name="wrap-${width}x${height}-$depth-$tool"
        assertArrayEquals(name,File(out,"$name.rgba").readBytes(),e.state(false)["pixels"] as ByteArray)
    }
}

}
