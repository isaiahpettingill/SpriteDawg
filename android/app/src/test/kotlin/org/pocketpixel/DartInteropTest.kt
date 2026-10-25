package org.pocketpixel

import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Optional independent Dart/native corpus comparison. See tool/aseprite_interop.dart. */
class DartInteropTest {
    @Test fun dartWritesAndCompositesMatchNativeOnUpstreamCorpus() {
        val path=System.getenv("SPRITEDAWG_INTEROP_DIR")
        assumeTrue("Set SPRITEDAWG_INTEROP_DIR to exported Dart corpus",path!=null)
        val dir=File(path!!)
        val files=dir.listFiles { f -> f.extension=="aseprite" }!!.sortedBy { it.name }
        assertTrue("Interop corpus must not be empty",files.isNotEmpty())
        for(file in files) {
            val original=javaClass.getResourceAsStream("/upstream/${file.name}")!!.use { Aseprite.read(it.readBytes()) }
            val dart=Aseprite.read(file.readBytes())
            assertEquals(file.name,original.frames.size,dart.frames.size)
            for(frame in original.frames.indices) {
                assertArrayEquals("${file.name} frame $frame native decode",original.composite(frame),dart.composite(frame))
                val colors=original.composite(frame)
                val rgba=ByteArray(colors.size*4)
                colors.forEachIndexed { i,c -> rgba[i*4]=(c ushr 16).toByte();rgba[i*4+1]=(c ushr 8).toByte();rgba[i*4+2]=c.toByte();rgba[i*4+3]=(c ushr 24).toByte() }
                assertArrayEquals("${file.name} frame $frame Dart render",rgba,File(dir,"${file.name}.$frame.rgba").readBytes())
            }
        }
    }
}
