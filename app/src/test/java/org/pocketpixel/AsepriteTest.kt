package org.pocketpixel

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Test

class AsepriteTest {
    private fun source(name: String) =
        javaClass.getResourceAsStream("/upstream/$name")!!.use { it.readBytes() }

    private fun round(d: Document, compressed: Boolean = true) =
        Aseprite.read(Aseprite.write(d, compressed))

    private fun example(): Document {
        val d = Document.create(5, 4)
        d.layers[0].name = "Bottom"
        d.layers.add(Layer("Top", opacity = 117))
        d.frames[0].cels.add(null)
        d.editable(0, 0).pixels[0] = 0x80123456.toInt()
        d.editable(0, 1).pixels[3] = 0xffabcdef.toInt()
        d.addFrame(0, true)
        d.frames[0].duration = 75
        d.frames[1].duration = 230
        return d
    }

    @Test
    fun createsValidHeader() {
        val b = Aseprite.write(Document.create())
        val h = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(b.size, h.int)
        assertEquals(0xA5E0, h.short.toInt() and 65535)
        assertEquals(32, round(Document.create()).width)
    }

    @Test
    fun identicalPixelData() {
        val d = example()
        val r = round(d)
        for (f in d.frames.indices) for (l in d.layers.indices) assertArrayEquals(
            d.resolved(f, l)!!.pixels,
            r.resolved(f, l)!!.pixels,
        )
    }

    @Test
    fun namesOrderAndOpacity() {
        val r = round(example())
        assertEquals(listOf("Bottom", "Top"), r.layers.map { it.name })
        assertEquals(117, r.layers[1].opacity)
    }

    @Test
    fun frameDurations() {
        assertEquals(listOf(75, 230), round(example()).frames.map { it.duration })
    }

    @Test
    fun transparencyAndHiddenRGB() {
        val d = Document.create(2, 1)
        d.editable(0, 0).pixels[0] = 0x00123456
        val r = round(d)
        assertEquals(0x00123456, r.resolved(0, 0)!!.pixels[0])
        assertEquals(0, r.composite(0)[0])
        assertEquals(0, r.composite(0)[1])
    }

    @Test
    fun rawAndCompressed() {
        val d = example()
        for (z in listOf(false, true)) assertArrayEquals(d.composite(0), round(d, z).composite(0))
    }

    @Test
    fun linkedCels() {
        val d = example()
        d.frames[1].cels[0] = Cel(1, 0, 0, 0, IntArray(0), 123, 0)
        val r = round(d)
        assertEquals(0, r.frames[1].cels[0]!!.link)
        assertEquals(123, r.resolved(1, 0)!!.opacity)
        assertArrayEquals(d.resolved(0, 0)!!.pixels, r.resolved(1, 0)!!.pixels)
    }

    @Test
    fun linkedEditingDetachesSafely() {
        val d = example()
        d.frames[1].cels[0] = Cel(0, 0, 0, 0, IntArray(0), 255, 0)
        val old = d.resolved(1, 0)!!.pixels.copyOf()
        d.editable(0, 0).pixels.fill(0)
        assertArrayEquals(old, d.resolved(1, 0)!!.pixels)
    }

    @Test
    fun animationTags() {
        val d = example()
        d.tags.add(Tag(0, 1, 3, 7, byteArrayOf(1, 2, 3), "Run"))
        val t = round(d).tags.single()
        assertEquals("Run", t.name)
        assertEquals(3, t.direction)
        assertEquals(7, t.repeat)
        assertEquals(1, t.to)
    }

    @Test
    fun allUserDataTargetsAndProperties() {
        val d = example()
        val props = byteArrayOf(8, 0, 0, 0, 0, 0, 0, 0)
        val u = UserData("{\"strength\": 12}", 0xff123456.toInt(), props)
        d.data = u
        d.layers[0].data = u
        d.frames[1].cels[1]!!.data = u
        d.tags.add(Tag(0, 1, 0, 0, byteArrayOf(1, 2, 3), "Attack", u))
        val r = round(d)
        for (a in listOf(r.data, r.layers[0].data, r.frames[1].cels[1]!!.data, r.tags[0].data)) {
            assertEquals(u.text, a!!.text)
            assertEquals(u.color, a.color)
            assertArrayEquals(props, a.properties)
        }
    }

    @Test
    fun grayscaleNativeRoundTrip() {
        val d = Document.create(2, 1)
        d.depth = 16
        d.editable(0, 0).pixels[0] = 0x80575757.toInt()
        val r = round(d)
        assertEquals(16, r.depth)
        assertEquals(0x80575757.toInt(), r.resolved(0, 0)!!.pixels[0])
        assertEquals(0xff4c4c4c.toInt(), d.drawingColor(0xffff0000.toInt(), 0))
    }

    @Test
    fun indexedNativeRoundTrip() {
        val d = Document.create(2, 1)
        d.depth = 8
        d.transparentIndex = 1
        d.frames[0].palette = intArrayOf(0xffff0000.toInt(), 0xff000000.toInt(), 0xff00ff00.toInt())
        d.editable(0, 0).pixels[0] = 2
        val r = round(d)
        assertEquals(8, r.depth)
        assertEquals(1, r.transparentIndex)
        assertArrayEquals(intArrayOf(2, 1), r.resolved(0, 0)!!.pixels)
        assertArrayEquals(intArrayOf(0xff00ff00.toInt(), 0), r.composite(0))
    }

    @Test
    fun celPositionOpacityAndOffCanvasPreserved() {
        val d = Document.create(2, 2)
        d.frames[0].cels[0] = Cel(-1, 1, 4, 1, intArrayOf(1, 2, 3, 4), 77)
        val r = round(d)
        assertEquals(-1, r.resolved(0, 0)!!.x)
        assertEquals(77, r.resolved(0, 0)!!.opacity)
        val c = r.editable(0, 0)
        assertEquals(1, c.pixels[c.width])
        assertEquals(4, c.pixels[c.width + 3])
    }

    @Test
    fun upstreamIndexedAndLayers() {
        val r = Aseprite.read(source("abcd.aseprite"))
        assertEquals(8, r.depth)
        assertEquals(listOf("a", "b", "c", "d"), r.layers.map { it.name })
        for (f in r.frames.indices) assertArrayEquals(r.composite(f), round(r).composite(f))
    }

    @Test
    fun upstreamSpecialTransparentIndex() {
        val d = Aseprite.read(source("bg-index-3.aseprite"))
        assertEquals(3, d.transparentIndex)
        assertEquals(8, d.depth)
        assertArrayEquals(d.composite(0), round(d).composite(0))
    }

    @Test
    fun upstreamTagsAndLinked() {
        val d = Aseprite.read(source("tags3.aseprite"))
        assertEquals(listOf("forward", "reverse", "pingpong"), d.tags.map { it.name })
        assertTrue(d.frames.any { it.cels.any { c -> c?.link != null } })
        val r = round(d)
        for (f in d.frames.indices) assertArrayEquals(d.composite(f), r.composite(f))
    }

    @Test
    fun upstreamEmptyFrames() {
        val d = Aseprite.read(source("1empty3.aseprite"))
        assertTrue(d.frames[1].cels.all { it == null })
        assertEquals(listOf("bg", "fg"), d.layers.map { it.name })
        val r = round(d)
        assertTrue(r.frames[1].cels.all { it == null })
    }

    @Test
    fun upstreamAllSupportedRoundTrip() {
        for (name in
            listOf(
                "2f-index-3x3.aseprite",
                "4f-index-4x4.aseprite",
                "point2frames.aseprite",
                "point4frames.aseprite",
                "link.aseprite",
                "cut_paste.aseprite",
                "tags3x123reps.aseprite",
            )) {
            val d = Aseprite.read(source(name))
            val r = round(d)
            assertEquals(d.frames.size, r.frames.size)
            for (f in d.frames.indices) assertArrayEquals(name, d.composite(f), r.composite(f))
        }
    }

    @Test
    fun unsupportedFeaturesRefusedWithoutChangingBytes() {
        for (name in
            listOf(
                "groups2.aseprite",
                "groups3abc.aseprite",
                "2x2tilemap2x2tile.aseprite",
                "2x3tilemap-indexed.aseprite",
                "3x2tilemap-grayscale.aseprite",
                "slices.aseprite",
                "slices-moving.aseprite",
                "z-order.aseprite",
                "file-tests-props.aseprite",
            )) {
            val bytes = source(name)
            val original = bytes.copyOf()
            try {
                Aseprite.read(bytes)
                fail("Should refuse $name")
            } catch (e: AsepriteException) {
                assertTrue(e.message!!.isNotBlank())
            }
            assertArrayEquals(original, bytes)
        }
    }

    @Test
    fun everyTruncationRejected() {
        val b = Aseprite.write(example())
        for (n in b.indices) {
            try {
                Aseprite.read(b.copyOf(n))
                fail("Accepted $n bytes")
            } catch (_: AsepriteException) {}
        }
    }

    @Test
    fun fuzzLengthsRejectedSafely() {
        val b = Aseprite.write(example())
        for (seed in 0..250) {
            val mutated = b.copyOf()
            val random = Random(seed)
            repeat(4) { mutated[random.nextInt(mutated.size)] = random.nextInt(256).toByte() }
            try {
                Aseprite.read(mutated)
            } catch (_: AsepriteException) {}
        }
    }

    @Test
    fun floodFillAndLine() {
        val c = Cel(0, 0, 5, 5, IntArray(25))
        Drawing.line(c, 0, 0, 4, 4, 1, 1)
        assertEquals(5, c.pixels.count { it == 1 })
        Drawing.fill(c, 4, 0, 2)
        assertEquals(10, c.pixels.count { it == 2 })
    }

    @Test
    fun undoAndRedo() {
        val d = example()
        val h = History()
        h.push(d)
        d.layers[0].name = "Edited"
        val old = h.undo(d)!!
        assertEquals("Bottom", old.layers[0].name)
        assertEquals("Edited", h.redo(old)!!.layers[0].name)
    }

    @Test
    fun typedPropertiesEditWithoutChangingOtherValues() {
        val input =
            UserProperties.write(
                listOf(
                    Property("strength", 6, ByteArray(0)).withText("12"),
                    Property("health", 7, ByteArray(0)).withText("4294967295"),
                    Property("boss", 1, ByteArray(0)).withText("true"),
                    Property("title", 13, ByteArray(0)).withText("Goblin α"),
                    Property("nested", 18, byteArrayOf(0, 0, 0, 0)),
                )
            )
        val values = UserProperties.read(input)
        assertEquals(
            listOf("12", "4294967295", "true", "Goblin α", "4 bytes (preserved)"),
            values.map { it.text() },
        )
        val updated = values.map { if (it.name == "strength") it.withText("19") else it }
        val d = Document.create()
        d.data = UserData("enemy", properties = UserProperties.write(updated))
        val result = UserProperties.read(round(d).data!!.properties)
        assertEquals("19", result[0].text())
        assertArrayEquals(values.last().raw, result.last().raw)
        for (j in 1..3) assertArrayEquals(values[j].raw, result[j].raw)
    }

    @Test
    fun actualAsepriteUserPropertyPayloads() {
        val data = source("file-tests-props.aseprite")
        val b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        var frame = 128
        var tested = 0
        while (frame < data.size) {
            val end = frame + b.getInt(frame)
            var c = frame + 16
            while (c < end) {
                val size = b.getInt(c)
                val type = b.getShort(c + 4).toInt() and 65535
                if (type == 0x2020) {
                    val flags = b.getInt(c + 6)
                    var p = c + 10
                    if (flags and 1 != 0) p += 2 + (b.getShort(p).toInt() and 65535)
                    if (flags and 2 != 0) p += 4
                    if (flags and 4 != 0 && b.getInt(p + 4) == 1 && b.getInt(p + 8) == 0) {
                        val props = data.copyOfRange(p, c + size)
                        val parsed = UserProperties.read(props)
                        assertTrue(parsed.isNotEmpty())
                        val d = Document.create()
                        d.data = UserData(properties = props)
                        assertArrayEquals(props, round(d).data!!.properties)
                        tested++
                    }
                }
                c += size
            }
            frame = end
        }
        assertTrue("Expected real upstream property maps", tested > 0)
    }

    @Test
    fun malformedPropertiesRejected() {
        val d = Document.create()
        d.data = UserData(properties = byteArrayOf(99, 0, 0, 0, 0, 0, 0, 0))
        try {
            round(d)
            fail("Bad property size accepted")
        } catch (_: AsepriteException) {}
    }

    @Test
    fun indexedPaletteSurvivesRemovingFirstFrame() {
        val d = Aseprite.read(source("4f-index-4x4.aseprite"))
        val pixels = d.composite(1)
        d.removeFrame(0)
        assertArrayEquals(pixels, round(d).composite(0))
    }

    @Test
    fun paintingKeepsOffCanvasPixels() {
        val c = Cel(-1, -1, 4, 4, IntArray(16) { 7 })
        Drawing.fill(c, 0, 0, 9, 2, 2)
        assertEquals(4, c.pixels.count { it == 9 })
        Drawing.dot(c, 0, 0, 3, 4, 2, 2)
        assertEquals(12, c.pixels.count { it == 7 })
    }

    @Test
    fun excessiveOffCanvasEditingRefusedWithoutMutation() {
        val d = Document.create(2048, 2048)
        val original = Cel(-32768, 0, 1, 1, intArrayOf(123))
        d.frames[0].cels[0] = original
        try {
            d.editable(0, 0)
            fail("Unsafe editing bounds accepted")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("safely"))
        }
        assertSame(original, d.frames[0].cels[0])
        assertEquals(123, original.pixels[0])
    }
}
