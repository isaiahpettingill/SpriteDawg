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
    run("spray",false,mapOf("tool" to "spray","points" to listOf(listOf(4,5),listOf(18,19),listOf(20,19)),"size" to 8,"density" to 70,"seed" to 42,"mirrorX" to true,"mirrorY" to true,"color" to 0x80c86432L))
    run("airbrush",true,mapOf("tool" to "airbrush","points" to listOf(listOf(5,5),listOf(5,5),listOf(13,15)),"size" to 9,"strength" to 20,"color" to 0x80c86432L,"mirrorX" to true,"mirrorY" to true))
    run("alpha",true,mapOf("tool" to "pencil","points" to listOf(listOf(5,5),listOf(13,15),listOf(5,5)),"size" to 5,"color" to 0x80c86432L,"mirrorX" to true))
    run("blur",true,mapOf("tool" to "blur","points" to listOf(listOf(8,8),listOf(20,12)),"size" to 5,"strength" to 67,"mirrorX" to true,"mirrorY" to true))
    run("jumble",true,mapOf("tool" to "jumble","points" to listOf(listOf(10,10),listOf(16,17)),"size" to 8,"strength" to 70,"seed" to 99,"mirrorX" to true))
    run("ellipse",false,mapOf("tool" to "ellipse","points" to listOf(listOf(18,22),listOf(3,5)),"filled" to true,"color" to 0x80c86432L,"mirrorX" to true))
}

}
