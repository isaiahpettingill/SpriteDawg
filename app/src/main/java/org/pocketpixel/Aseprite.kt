package org.pocketpixel

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.DeflaterOutputStream
import java.util.zip.Inflater

class AsepriteException(message: String) : IllegalArgumentException(message)

private fun checkFile(ok: Boolean, message: String) {
    if (!ok) throw AsepriteException(message)
}

internal class Reader(val bytes: ByteArray) {
    var pos = 0
    val left
        get() = bytes.size - pos

    fun take(n: Int): ByteArray {
        checkFile(n >= 0 && n <= left, "Truncated Aseprite data")
        return bytes.copyOfRange(pos, pos + n).also { pos += n }
    }

    fun u8() = take(1)[0].toInt() and 255

    fun u16() = u8() or (u8() shl 8)

    fun s16() = u16().toShort().toInt()

    fun u32(): Int {
        val v = u16().toLong() or (u16().toLong() shl 16)
        checkFile(v <= Int.MAX_VALUE, "Aseprite field exceeds safe limit")
        return v.toInt()
    }

    fun str(): String {
        val b = take(u16())
        return Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(b)).toString()
    }

    fun zero(n: Int) {
        checkFile(
            take(n).all { it == 0.toByte() },
            "Unsupported nonzero reserved data; editing refused",
        )
    }

    fun end() {
        checkFile(left == 0, "Unexpected trailing chunk data; editing refused")
    }
}

private class Writer {
    val out = ByteArrayOutputStream()

    fun b(v: Int) {
        out.write(v)
    }

    fun w(v: Int) {
        b(v)
        b(v ushr 8)
    }

    fun d(v: Int) {
        w(v)
        w(v ushr 16)
    }

    fun bytes(v: ByteArray) {
        out.write(v)
    }

    fun zeros(n: Int) {
        bytes(ByteArray(n))
    }

    fun str(s: String) {
        val a = s.toByteArray(Charsets.UTF_8)
        require(a.size <= 65535)
        w(a.size)
        bytes(a)
    }

    fun result() = out.toByteArray()
}

object Aseprite {
    const val MAX_FILE = 64 * 1024 * 1024

    fun read(bytes: ByteArray): Document {
        try {
            return decode(bytes)
        } catch (e: AsepriteException) {
            throw e
        } catch (e: Exception) {
            throw AsepriteException("Invalid Aseprite file: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    private fun decode(bytes: ByteArray): Document {
        checkFile(bytes.size in 128..MAX_FILE, "File is truncated or exceeds 64 MiB")
        val r = Reader(bytes)
        checkFile(r.u32() == bytes.size, "Incorrect file size")
        checkFile(r.u16() == 0xA5E0, "Not an Aseprite file")
        val count = r.u16()
        val w = r.u16()
        val h = r.u16()
        val depth = r.u16()
        val flags = r.u32()
        val speed = r.u16()
        checkFile(
            count in 1..4096 &&
                w in 1..2048 &&
                h in 1..2048 &&
                w.toLong() * h <= Document.MAX_PIXELS,
            "Sprite exceeds safe dimensions/frame limit",
        )
        checkFile(depth in listOf(8, 16, 32), "Unsupported color depth $depth")
        checkFile(flags and 7 == flags, "Unsupported header flags")
        r.zero(8)
        val transparent = r.u8()
        r.take(3)
        r.u16()
        val pw = r.u8()
        val ph = r.u8()
        checkFile(pw == 0 || ph == 0 || pw == ph, "Non-square pixel ratios are not supported")
        r.take(8)
        r.zero(84)
        val d =
            Document(
                w,
                h,
                mutableListOf(),
                mutableListOf(),
                header = bytes.copyOf(128),
                depth = depth,
                transparentIndex = transparent,
            )
        var currentPalette = IntArray(256) { 0xff000000.toInt() }
        var paletteSeen = false
        var totalPixels = 0L
        var spriteData: UserData? = null
        repeat(count) { fi ->
            val start = r.pos
            val size = r.u32()
            checkFile(size >= 16 && size <= r.left + 4, "Invalid frame size")
            val fr = Reader(r.take(size - 4))
            checkFile(fr.u16() == 0xF1FA, "Invalid frame magic")
            val old = fr.u16()
            val duration = fr.u16()
            fr.zero(2)
            val newer = fr.u32()
            val chunks = if (newer == 0) old else newer
            checkFile(chunks <= 100000 && chunks <= fr.left / 6, "Invalid chunk count")
            val frame = Frame(if (duration == 0) speed.coerceAtLeast(1) else duration)
            d.frames.add(frame)
            val initialPalette = currentPalette.copyOf()
            var modernPalette = false
            val pending = mutableMapOf<Int, Cel>()
            var attach: ((UserData) -> Unit)? = null
            var tagTargets: List<Tag> = emptyList()
            var tagAt = 0
            repeat(chunks) {
                val cs = fr.u32()
                val type = fr.u16()
                checkFile(cs >= 6 && cs - 6 <= fr.left, "Invalid chunk size")
                val raw = fr.take(cs - 6)
                val c = Reader(raw)
                if (type != 0x2020) {
                    attach = null
                    tagTargets = emptyList()
                    tagAt = 0
                }
                when (type) {
                    0x2004 -> {
                        checkFile(fi == 0, "Animated layer definitions are unsupported")
                        val lf = c.u16()
                        val lt = c.u16()
                        val level = c.u16()
                        c.take(4)
                        val blend = c.u16()
                        val opacity = c.u8()
                        c.zero(3)
                        val name = c.str()
                        checkFile(
                            lt == 0 && level == 0,
                            if (lt == 2) "Tilemap layers cannot be safely edited yet"
                            else "Group layers cannot be safely edited yet",
                        )
                        checkFile(blend == 0, "Blend mode $blend cannot be safely edited yet")
                        checkFile(lf and 64 == 0, "Reference layers cannot be safely edited yet")
                        checkFile(lf and 127 == lf, "Unknown layer flags")
                        val uuid = if (flags and 4 != 0) c.take(16) else null
                        val layer =
                            Layer(
                                name,
                                lf and 1 != 0,
                                if (flags and 1 != 0) opacity else 255,
                                lf,
                                uuid,
                            )
                        d.layers.add(layer)
                        attach = { layer.data = it }
                        checkFile(d.layers.size <= 256, "Too many layers")
                    }
                    0x2005 -> {
                        val li = c.u16()
                        val x = c.s16()
                        val y = c.s16()
                        val opacity = c.u8()
                        val ct = c.u16()
                        val z = c.s16()
                        c.zero(5)
                        checkFile(z == 0, "Cel z-index changes cannot be safely edited yet")
                        checkFile(!pending.containsKey(li), "Duplicate cel in layer")
                        val cel =
                            when (ct) {
                                1 -> Cel(x, y, 0, 0, IntArray(0), opacity, c.u16())
                                0,
                                2 -> {
                                    val cw = c.u16()
                                    val ch = c.u16()
                                    val n = cw.toLong() * ch
                                    checkFile(
                                        cw > 0 && ch > 0 && n <= Document.MAX_PIXELS,
                                        "Invalid or oversized cel",
                                    )
                                    totalPixels += n
                                    checkFile(
                                        totalPixels <= 16_777_216,
                                        "Decoded document exceeds 64 MiB pixel budget",
                                    )
                                    val expected = n.toInt() * (depth / 8)
                                    val payload = c.take(c.left)
                                    val data = if (ct == 0) payload else inflate(payload, expected)
                                    checkFile(data.size == expected, "Incorrect cel pixel length")
                                    val pr = Reader(data)
                                    val pixels =
                                        IntArray(n.toInt()) {
                                            when (depth) {
                                                8 -> pr.u8()
                                                16 -> {
                                                    val v = pr.u8()
                                                    val a = pr.u8()
                                                    (a shl 24) or (v * 0x010101)
                                                }
                                                else -> {
                                                    val red = pr.u8()
                                                    val green = pr.u8()
                                                    val blue = pr.u8()
                                                    val a = pr.u8()
                                                    (a shl 24) or
                                                        (red shl 16) or
                                                        (green shl 8) or
                                                        blue
                                                }
                                            }
                                        }
                                    Cel(x, y, cw, ch, pixels, opacity)
                                }
                                else ->
                                    throw AsepriteException(
                                        "Tilemap or unknown cel type $ct cannot be safely edited"
                                    )
                            }
                        pending[li] = cel
                        attach = { cel.data = it }
                    }
                    0x2018 -> {
                        checkFile(d.tags.isEmpty(), "Multiple tag definitions unsupported")
                        val n = c.u16()
                        c.zero(8)
                        repeat(n) {
                            val from = c.u16()
                            val to = c.u16()
                            val dir = c.u8()
                            val rep = c.u16()
                            c.zero(6)
                            val color = c.take(3)
                            c.zero(1)
                            val name = c.str()
                            checkFile(from <= to && to < count && dir <= 3, "Invalid animation tag")
                            d.tags.add(Tag(from, to, dir, rep, color, name))
                        }
                        tagTargets = d.tags.toList()
                    }
                    0x2019 -> {
                        if (!modernPalette) {
                            currentPalette = initialPalette.copyOf()
                            modernPalette = true
                        }
                        val n = c.u32()
                        val first = c.u32()
                        val last = c.u32()
                        c.zero(8)
                        checkFile(
                            n in 1..65536 && first <= last && last < n,
                            "Invalid palette range",
                        )
                        if (depth == 8) checkFile(n <= 256, "Indexed palette exceeds 256 entries")
                        currentPalette = currentPalette.copyOf(n)
                        for (i in first..last) {
                            val ef = c.u16()
                            checkFile(ef and 1 == ef, "Unknown palette flags")
                            val red = c.u8()
                            val green = c.u8()
                            val blue = c.u8()
                            val a = c.u8()
                            currentPalette[i] = (a shl 24) or (red shl 16) or (green shl 8) or blue
                            if (ef and 1 != 0) c.str()
                        }
                        paletteSeen = true
                        frame.metadata.add(type to raw)
                        attach = { spriteData = it }
                    }
                    0x0004,
                    0x0011 -> {
                        val packets = c.u16()
                        var index = 0
                        repeat(packets) {
                            index += c.u8()
                            val n = c.u8().let { if (it == 0) 256 else it }
                            checkFile(index + n <= 256, "Invalid old palette")
                            repeat(n) {
                                fun channel(): Int {
                                    val v = c.u8()
                                    checkFile(type != 0x11 || v <= 63, "Invalid 6-bit palette")
                                    return if (type == 0x11) (v * 255 + 31) / 63 else v
                                }
                                val red = channel()
                                val green = channel()
                                val blue = channel()
                                if (!modernPalette && index < currentPalette.size)
                                    currentPalette[index] =
                                        (255 shl 24) or (red shl 16) or (green shl 8) or blue
                                index++
                            }
                        }
                        paletteSeen = true
                        frame.metadata.add(type to raw)
                        attach = { spriteData = it }
                    }
                    0x2007 -> {
                        val profile = c.u16()
                        val pf = c.u16()
                        val gamma = c.u32()
                        c.zero(8)
                        checkFile(
                            profile in 0..1 && (pf == 0 || (pf == 1 && gamma == 144179)),
                            "Embedded ICC or custom gamma color profiles cannot be rendered safely",
                        )
                        frame.metadata.add(type to raw)
                    }
                    0x2020 -> {
                        val u = readData(c)
                        if (tagTargets.isNotEmpty()) {
                            checkFile(tagAt < tagTargets.size, "Excess tag user data")
                            tagTargets[tagAt++].data = u
                        } else {
                            checkFile(
                                attach != null,
                                "Unassociated user data cannot be preserved safely",
                            )
                            attach!!(u)
                            attach = null
                        }
                    }
                    else ->
                        throw AsepriteException(
                            when (type) {
                                0x2022 -> "Slices cannot be safely edited yet"
                                0x2006 -> "Precise cel transforms cannot be safely edited yet"
                                0x2008 -> "External file references cannot be safely edited offline"
                                else ->
                                    "Unsupported chunk 0x${type.toString(16)}; editing refused to preserve metadata"
                            }
                        )
                }
                c.end()
            }
            fr.end()
            checkFile(r.pos == start + size, "Invalid frame boundary")
            checkFile(pending.keys.all { it in d.layers.indices }, "Cel refers to missing layer")
            frame.cels.addAll(d.layers.indices.map { pending[it] })
            frame.palette = currentPalette.copyOf()
        }
        r.end()
        checkFile(d.layers.isNotEmpty(), "Sprite has no image layers")
        checkFile(
            depth != 8 || paletteSeen,
            "Indexed file has no explicit palette; default palette cannot be inferred safely",
        )
        for (f in d.frames.indices) for (l in d.layers.indices) {
            val c = d.frames[f].cels[l] ?: continue
            if (c.link != null) {
                checkFile(c.link!! in 0 until f, "Linked cel must reference an earlier frame")
                d.resolved(f, l)
            }
            if (depth == 8)
                checkFile(
                    (d.resolved(f, l)?.pixels ?: IntArray(0)).all {
                        it in d.frames[f].palette.indices
                    },
                    "Pixel index outside palette",
                )
        }
        d.data = spriteData
        d.palette.clear()
        d.palette.addAll(d.frames[0].palette.toList())
        return d
    }

    private fun readData(c: Reader): UserData {
        val flags = c.u32()
        checkFile(flags and 7 == flags, "Unknown user data flags")
        val text = if (flags and 1 != 0) c.str() else null
        val color =
            if (flags and 2 != 0) {
                val r = c.u8()
                val g = c.u8()
                val b = c.u8()
                val a = c.u8()
                (a shl 24) or (r shl 16) or (g shl 8) or b
            } else null
        val props =
            if (flags and 4 != 0)
                c.take(c.left).also {
                    checkFile(it.size >= 8, "Truncated user data properties")
                    UserProperties.read(it)
                }
            else null
        return UserData(text, color, props)
    }

    private fun inflate(data: ByteArray, n: Int): ByteArray {
        val z = Inflater()
        try {
            z.setInput(data)
            val out = ByteArray(n)
            var p = 0
            while (p < n && !z.finished()) {
                val k = z.inflate(out, p, n - p)
                checkFile(k > 0, "Invalid or truncated zlib cel")
                p += k
            }
            val extra = ByteArray(1)
            val k = z.inflate(extra)
            checkFile(
                p == n && k == 0 && z.finished() && z.remaining == 0,
                "Incorrect zlib cel length",
            )
            return out
        } finally {
            z.end()
        }
    }

    private fun chunk(type: Int, block: Writer.() -> Unit): ByteArray {
        val data = Writer().apply(block).result()
        return Writer()
            .apply {
                d(data.size + 6)
                w(type)
                bytes(data)
            }
            .result()
    }

    private fun userChunk(data: UserData?) =
        data?.let { u ->
            chunk(0x2020) {
                d(
                    (if (u.text != null) 1 else 0) or
                        (if (u.color != null) 2 else 0) or
                        (if (u.properties != null) 4 else 0)
                )
                u.text?.let { str(it) }
                u.color?.let {
                    b(it ushr 16)
                    b(it ushr 8)
                    b(it)
                    b(it ushr 24)
                }
                u.properties?.let { bytes(it) }
            }
        }

    fun write(doc: Document, compressed: Boolean = true): ByteArray {
        require(doc.frames.isNotEmpty() && doc.layers.isNotEmpty())
        val uuid = doc.layers.any { it.uuid != null }
        val frames =
            doc.frames.mapIndexed { fi, f ->
                val chunks = mutableListOf<ByteArray>()
                fun addUser(u: UserData?) {
                    userChunk(u)?.let { chunks.add(it) }
                }
                if (fi == 0)
                    for (layer in doc.layers) {
                        chunks.add(
                            chunk(0x2004) {
                                w((layer.flags and 1.inv()) or if (layer.visible) 1 else 0)
                                w(0)
                                w(0)
                                w(0)
                                w(0)
                                w(0)
                                b(layer.opacity)
                                zeros(3)
                                str(layer.name)
                                if (uuid) bytes(layer.uuid ?: ByteArray(16))
                            }
                        )
                        addUser(layer.data)
                    }
                // Preserve palette names and legacy packet layouts byte-for-byte when present.
                val paletteChunks = f.metadata.filter { it.first in listOf(4, 17, 0x2019) }
                f.metadata
                    .filter { it.first == 0x2007 }
                    .forEach { (t, b) -> chunks.add(chunk(t) { bytes(b) }) }
                if (fi == 0) {
                    val pal = if (f.palette.isNotEmpty()) f.palette else doc.palette.toIntArray()
                    chunks.add(
                        chunk(0x2019) {
                            d(pal.size)
                            d(0)
                            d(pal.size - 1)
                            zeros(8)
                            for (c in pal) {
                                w(0)
                                b(c ushr 16)
                                b(c ushr 8)
                                b(c)
                                b(c ushr 24)
                            }
                        }
                    )
                }
                paletteChunks.forEach { (t, b) -> chunks.add(chunk(t) { bytes(b) }) }
                if (
                    fi > 0 &&
                        paletteChunks.isEmpty() &&
                        !f.palette.contentEquals(doc.frames[fi - 1].palette)
                ) {
                    val pal = if (f.palette.isNotEmpty()) f.palette else doc.palette.toIntArray()
                    chunks.add(
                        chunk(0x2019) {
                            d(pal.size)
                            d(0)
                            d(pal.size - 1)
                            zeros(8)
                            for (c in pal) {
                                w(0)
                                b(c ushr 16)
                                b(c ushr 8)
                                b(c)
                                b(c ushr 24)
                            }
                        }
                    )
                }
                if (fi == 0) addUser(doc.data)
                if (fi == 0 && doc.tags.isNotEmpty()) {
                    chunks.add(
                        chunk(0x2018) {
                            w(doc.tags.size)
                            zeros(8)
                            for (t in doc.tags) {
                                w(t.from)
                                w(t.to)
                                b(t.direction)
                                w(t.repeat)
                                zeros(6)
                                bytes(t.color)
                                b(0)
                                str(t.name)
                            }
                        }
                    )
                    if (doc.tags.any { it.data != null })
                        doc.tags.forEach { addUser(it.data ?: UserData()) }
                }
                f.cels.forEachIndexed { li, c ->
                    if (c != null) {
                        chunks.add(
                            chunk(0x2005) {
                                w(li)
                                w(c.x)
                                w(c.y)
                                b(c.opacity)
                                w(if (c.link != null) 1 else if (compressed) 2 else 0)
                                w(0)
                                zeros(5)
                                if (c.link != null) w(c.link!!)
                                else {
                                    w(c.width)
                                    w(c.height)
                                    val raw =
                                        Writer()
                                            .apply {
                                                for (v in c.pixels) when (doc.depth) {
                                                    8 -> b(v)
                                                    16 -> {
                                                        b(v)
                                                        b(v ushr 24)
                                                    }
                                                    else -> {
                                                        b(v ushr 16)
                                                        b(v ushr 8)
                                                        b(v)
                                                        b(v ushr 24)
                                                    }
                                                }
                                            }
                                            .result()
                                    if (compressed) {
                                        val out = ByteArrayOutputStream()
                                        DeflaterOutputStream(out).use { it.write(raw) }
                                        bytes(out.toByteArray())
                                    } else bytes(raw)
                                }
                            }
                        )
                        addUser(c.data)
                    }
                }
                Writer()
                    .apply {
                        d(16 + chunks.sumOf { it.size })
                        w(0xF1FA)
                        w(chunks.size.coerceAtMost(65535))
                        w(f.duration)
                        zeros(2)
                        d(chunks.size)
                        chunks.forEach { bytes(it) }
                    }
                    .result()
            }
        val header =
            doc.header?.copyOf()
                ?: ByteArray(128).also {
                    it[34] = 1
                    it[35] = 1
                }
        val b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        b.putInt(0, 128 + frames.sumOf { it.size })
        b.putShort(4, 0xA5E0.toShort())
        b.putShort(6, doc.frames.size.toShort())
        b.putShort(8, doc.width.toShort())
        b.putShort(10, doc.height.toShort())
        b.putShort(12, doc.depth.toShort())
        b.putInt(14, 1 or if (uuid) 4 else 0)
        b.putShort(18, doc.frames[0].duration.toShort())
        b.put(28, doc.transparentIndex.toByte())
        return Writer()
            .apply {
                bytes(header)
                frames.forEach { bytes(it) }
            }
            .result()
            .also { checkFile(it.size <= MAX_FILE, "Saved document exceeds 64 MiB") }
    }
}
