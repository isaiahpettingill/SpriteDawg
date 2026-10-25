package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class ThumbnailTest {
    @Suppress("UNCHECKED_CAST")
    private fun images(e: EditorEngine, args: Map<String, Any?>) = e.thumbnails(args)["thumbnails"] as List<Map<String, Any?>>
    @Test fun nearestNeighborPreservesAspectPixelsAndEditorState() {
        val d = Document.create(8, 4)
        val cel = d.editable(0, 0)
        for (y in 0..3) for (x in 0..7) cel.pixels[y*8+x] = 0xff000000.toInt() or (x shl 16) or (y shl 8)
        d.addFrame(0, true)
        val e = EditorEngine().apply { replace(d); select(mapOf("frame" to 1)) }
        val original = Aseprite.write(e.document)
        val image = images(e, mapOf("frames" to listOf(0), "maxSize" to 4)).single()
        assertEquals(4, image["width"]); assertEquals(2, image["height"])
        val pixels = image["pixels"] as ByteArray
        assertEquals(32, pixels.size)
        assertArrayEquals(byteArrayOf(0,0,0,255.toByte(), 2,0,0,255.toByte()), pixels.copyOfRange(0,8))
        assertArrayEquals(byteArrayOf(0,2,0,255.toByte()), pixels.copyOfRange(16,20))
        assertEquals(1, e.frame); assertFalse(e.dirty); assertFalse(e.state(false)["canUndo"] as Boolean)
        assertArrayEquals(original, Aseprite.write(e.document))
    }
    @Test fun sizeIsCappedAndSmallAssetsAreNotUpscaled() {
        val e = EditorEngine()
        val small = images(e, mapOf("frames" to listOf(0), "maxSize" to 1000)).single()
        assertEquals(32, small["width"])
        e.replace(Document.create(256, 128))
        val large = images(e, mapOf("frames" to listOf(0), "maxSize" to 1000)).single()
        assertEquals(64, large["width"]); assertEquals(32, large["height"])
    }
    @Test fun invalidAndUnboundedRequestsAreRefused() {
        for (args in listOf(mapOf("frames" to List(33) { 0 }), mapOf("frames" to listOf(1)), mapOf("frames" to listOf(0.5)), mapOf("frames" to listOf(0), "maxSize" to 0))) {
            try { images(EditorEngine(), args); fail("Must reject $args") } catch (_: IllegalArgumentException) { }
        }
    }
}
