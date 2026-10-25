package org.pocketpixel

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Preserves each typed value verbatim; scalar editing never rewrites nested values. */
data class Property(val name: String, val type: Int, val raw: ByteArray) {
    val editable
        get() = type in 1..13

    fun text(): String {
        val b = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        return when (type) {
            1 -> (b.get().toInt() != 0).toString()
            2 -> b.get().toString()
            3 -> (b.get().toInt() and 255).toString()
            4 -> b.short.toString()
            5 -> (b.short.toInt() and 65535).toString()
            6 -> b.int.toString()
            7 -> (b.int.toLong() and 0xffffffffL).toString()
            8 -> b.long.toString()
            9 -> java.lang.Long.toUnsignedString(b.long)
            10 -> (b.int / 65536.0).toString()
            11 -> b.float.toString()
            12 -> b.double.toString()
            13 -> Reader(raw).str()
            else -> "${raw.size} bytes (preserved)"
        }
    }

    fun withText(value: String): Property {
        val b = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
        fun integer(min: Long, max: Long): Long {
            val n = value.toLong()
            require(n in min..max) { "$name must be between $min and $max" }
            return n
        }
        val bytes =
            when (type) {
                1 -> {
                    require(value == "true" || value == "false") { "Use true or false" }
                    byteArrayOf(if (value == "true") 1 else 0)
                }
                2 -> byteArrayOf(integer(-128, 127).toByte())
                3 -> byteArrayOf(integer(0, 255).toByte())
                4 -> b.putShort(integer(-32768, 32767).toShort()).array().copyOf(2)
                5 -> b.putShort(integer(0, 65535).toShort()).array().copyOf(2)
                6 ->
                    b.putInt(integer(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt())
                        .array()
                        .copyOf(4)
                7 -> b.putInt(integer(0, 0xffffffffL).toInt()).array().copyOf(4)
                8 -> b.putLong(value.toLong()).array()
                9 -> b.putLong(java.lang.Long.parseUnsignedLong(value)).array()
                10 -> {
                    val n = value.toDouble() * 65536
                    require(n.isFinite() && n >= Int.MIN_VALUE && n <= Int.MAX_VALUE)
                    b.putInt(n.toInt()).array().copyOf(4)
                }
                11 -> {
                    val n = value.toFloat()
                    require(n.isFinite())
                    b.putFloat(n).array().copyOf(4)
                }
                12 -> {
                    val n = value.toDouble()
                    require(n.isFinite())
                    b.putDouble(n).array()
                }
                13 -> {
                    val text = value.toByteArray(Charsets.UTF_8)
                    require(text.size <= 65535)
                    byteArrayOf(text.size.toByte(), (text.size ushr 8).toByte()) + text
                }
                else -> error("This property type is preserved read-only")
            }
        return copy(raw = bytes)
    }
}

object UserProperties {
    fun read(bytes: ByteArray?): List<Property> {
        if (bytes == null) return emptyList()
        val r = Reader(bytes)
        require(r.u32() == bytes.size) { "Invalid user properties length" }
        val maps = r.u32()
        require(maps in 0..1) { "Multiple user property maps cannot be edited safely" }
        val result = mutableListOf<Property>()
        if (maps == 1) {
            require(r.u32() == 0) { "Extension properties require an external reference" }
            val count = r.u32()
            require(count <= r.left / 4) { "Invalid property count" }
            repeat(count) {
                val name = r.str()
                val type = r.u16()
                val start = r.pos
                skip(r, type, 0)
                result.add(Property(name, type, bytes.copyOfRange(start, r.pos)))
            }
        }
        r.end()
        return result
    }

    private fun skip(r: Reader, type: Int, depth: Int) {
        require(depth <= 128) { "Properties exceed nesting limit" }
        when (type) {
            1,
            2,
            3 -> r.take(1)
            4,
            5 -> r.take(2)
            6,
            7,
            10,
            11 -> r.take(4)
            8,
            9,
            12,
            14,
            15 -> r.take(8)
            16,
            19 -> r.take(16)
            13 -> r.str()
            17 -> {
                val count = r.u32()
                val element = r.u16()
                require(count <= r.left) { "Invalid vector count" }
                repeat(count) { skip(r, if (element == 0) r.u16() else element, depth + 1) }
            }
            18 -> {
                val count = r.u32()
                require(count <= r.left / 4) { "Invalid nested property count" }
                repeat(count) {
                    r.str()
                    skip(r, r.u16(), depth + 1)
                }
            }
            else -> error("Unsupported user property type 0x${type.toString(16)}")
        }
    }

    fun write(properties: List<Property>): ByteArray {
        val out = ByteArrayOutputStream()
        fun w(n: Int) {
            out.write(n)
            out.write(n ushr 8)
        }
        fun d(n: Int) {
            w(n)
            w(n ushr 16)
        }
        d(0)
        d(1)
        d(0)
        d(properties.size)
        for (p in properties) {
            val name = p.name.toByteArray(Charsets.UTF_8)
            require(name.size <= 65535)
            w(name.size)
            out.write(name)
            w(p.type)
            out.write(p.raw)
        }
        val bytes = out.toByteArray()
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).putInt(bytes.size)
        return bytes
    }
}
