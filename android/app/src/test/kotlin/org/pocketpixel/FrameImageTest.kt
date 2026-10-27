package org.pocketpixel

import org.junit.Assert.*
import org.junit.Test

class FrameImageTest {
    @Test fun fullResolutionPreviewDoesNotSelectOrMutateHistory() {
        val e = EditorEngine()
        e.replace(Document(2, 1, mutableListOf(Layer("Ink")), mutableListOf(
            Frame(cels = mutableListOf(Cel(0, 0, 2, 1, intArrayOf(0x804488aa.toInt(), 0)))),
            Frame(cels = mutableListOf(Cel(0, 0, 0, 0, intArrayOf(), link = 0)))
        )))
        e.select(mapOf("frame" to 1, "layer" to 0))
        val before = Aseprite.write(e.document)
        val state = e.state(false)
        val preview = e.frameImage(mapOf("frame" to 0))
        assertEquals(0, preview["frame"])
        assertEquals(2, preview["width"])
        assertEquals(1, preview["height"])
        assertArrayEquals(byteArrayOf(0x44, 0x88.toByte(), 0xaa.toByte(), 0x80.toByte(), 0, 0, 0, 0), preview["pixels"] as ByteArray)
        assertEquals(1, e.frame)
        assertArrayEquals(before, Aseprite.write(e.document))
        assertEquals(state["dirty"], e.state(false)["dirty"])
        assertEquals(state["canUndo"], e.state(false)["canUndo"])
        for (value in listOf(-1, 2, 0.5, "0", null)) {
            try {
                e.frameImage(mapOf("frame" to value))
                fail("Invalid preview frame accepted")
            } catch (_: IllegalArgumentException) {}
            assertArrayEquals(before, Aseprite.write(e.document))
        }
    }
}
