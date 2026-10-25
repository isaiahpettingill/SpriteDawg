package org.pocketpixel

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.util.zip.CRC32
import java.util.zip.InflaterInputStream
import org.junit.Assert.*
import org.junit.Test

class PngTest {
    // Android compilation omits java.desktop; the JVM unit-test runtime provides it.
    // Reflection keeps the independent PNG decoder test without Android API imports.
    private fun readPng(bytes: ByteArray): Any = Class.forName("javax.imageio.ImageIO")
        .getMethod("read", java.io.InputStream::class.java)
        .invoke(null, ByteArrayInputStream(bytes))!!
    private fun dimension(image: Any, method: String): Int =
        image.javaClass.getMethod(method).invoke(image) as Int
    private fun pixels(image: Any, width: Int, height: Int): IntArray = image.javaClass
        .getMethod("getRGB", Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
            IntArray::class.java, Integer.TYPE, Integer.TYPE)
        .invoke(image, 0, 0, width, height, null, 0, width) as IntArray

    @Test fun straightAlphaBytesAreNotPremultipliedOrQuantized() {
        val pixels = intArrayOf(0x80c86432.toInt(), 0x01010203)
        val encoded = Png.encode(2, 1, pixels)
        val input = DataInputStream(ByteArrayInputStream(encoded))
        assertEquals(0x89504e470d0a1a0aUL.toLong(), input.readLong())
        val compressed = ByteArrayOutputStream()
        val types = mutableListOf<String>()
        while (input.available() > 0) {
            val length = input.readInt()
            val type = ByteArray(4).also { input.readFully(it) }
            val bytes = ByteArray(length).also { input.readFully(it) }
            val expectedCrc = input.readInt().toLong() and 0xffffffffL
            val crc = CRC32().apply { update(type); update(bytes) }
            assertEquals(expectedCrc, crc.value)
            val name = type.toString(Charsets.US_ASCII)
            types.add(name)
            when (name) {
                "IHDR" -> DataInputStream(ByteArrayInputStream(bytes)).use {
                    assertEquals(2, it.readInt()); assertEquals(1, it.readInt())
                    assertEquals(8, it.readUnsignedByte()); assertEquals(6, it.readUnsignedByte())
                    assertEquals(0, it.readUnsignedByte()); assertEquals(0, it.readUnsignedByte())
                    assertEquals(0, it.readUnsignedByte()); assertEquals(0, it.available())
                }
                "IDAT" -> compressed.write(bytes)
                "IEND" -> assertEquals(0, length)
            }
        }
        assertEquals(listOf("IHDR", "IDAT", "IEND"), types)
        val raw = InflaterInputStream(ByteArrayInputStream(compressed.toByteArray())).use { it.readBytes() }
        assertArrayEquals(byteArrayOf(0, 200.toByte(), 100, 50, 128.toByte(), 1, 2, 3, 1), raw)
        // Independent JDK PNG implementation confirms the emitted image's exact colors.
        val image = readPng(encoded)
        assertEquals(2, dimension(image, "getWidth")); assertEquals(1, dimension(image, "getHeight"))
        assertArrayEquals(pixels, pixels(image, 2, 1))
    }
    @Test fun everyRowGetsAFilterByteAndHiddenRgbSurvives() {
        val pixels = intArrayOf(0x00123456, 0xffabcdef.toInt())
        val image = readPng(Png.encode(1, 2, pixels))
        assertArrayEquals(pixels, pixels(image, 1, 2))
    }
}
