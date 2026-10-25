package org.pocketpixel

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream

/** PNG stores straight RGBA: do not round-trip through Android's premultiplied Bitmap. */
object Png {
    fun encode(width: Int, height: Int, pixels: IntArray): ByteArray {
        require(width > 0 && height > 0 && width.toLong() * height == pixels.size.toLong())
        val output = ByteArrayOutputStream()
        val data = DataOutputStream(output)
        data.write(byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val name = type.toByteArray(Charsets.US_ASCII)
            val crc = CRC32().apply { update(name); update(bytes) }
            data.writeInt(bytes.size)
            data.write(name)
            data.write(bytes)
            data.writeInt(crc.value.toInt())
        }
        val header = ByteArrayOutputStream()
        DataOutputStream(header).use {
            it.writeInt(width); it.writeInt(height)
            it.writeByte(8) // bit depth
            it.writeByte(6) // straight RGBA
            it.writeByte(0); it.writeByte(0); it.writeByte(0)
        }
        chunk("IHDR", header.toByteArray())
        val compressed = ByteArrayOutputStream()
        DeflaterOutputStream(compressed).use { z ->
            val row = ByteArray(1 + width * 4) // filter byte 0 (None)
            for (y in 0 until height) {
                for (x in 0 until width) {
                    val color = pixels[y * width + x]
                    val index = 1 + x * 4
                    row[index] = (color ushr 16).toByte()
                    row[index + 1] = (color ushr 8).toByte()
                    row[index + 2] = color.toByte()
                    row[index + 3] = (color ushr 24).toByte()
                }
                z.write(row)
            }
        }
        chunk("IDAT", compressed.toByteArray())
        chunk("IEND", ByteArray(0))
        return output.toByteArray()
    }
}
