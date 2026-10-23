package org.pocketpixel

import kotlin.math.*

data class UserData(
    val text: String? = null,
    val color: Int? = null,
    val properties: ByteArray? = null,
)

data class Layer(
    var name: String,
    var visible: Boolean = true,
    var opacity: Int = 255,
    var flags: Int = 3,
    val uuid: ByteArray? = null,
    var data: UserData? = null,
)

data class Cel(
    var x: Int,
    var y: Int,
    var width: Int,
    var height: Int,
    var pixels: IntArray,
    var opacity: Int = 255,
    var link: Int? = null,
    var data: UserData? = null,
) {
    fun copyDeep() = copy(pixels = pixels.copyOf())
}

data class Frame(
    var duration: Int = 100,
    val cels: MutableList<Cel?> = mutableListOf(),
    val metadata: MutableList<Pair<Int, ByteArray>> = mutableListOf(),
    var palette: IntArray = IntArray(0),
)

data class Tag(
    var from: Int,
    var to: Int,
    val direction: Int,
    val repeat: Int,
    val color: ByteArray,
    val name: String,
    var data: UserData? = null,
)

class Document(
    var width: Int,
    var height: Int,
    val layers: MutableList<Layer>,
    val frames: MutableList<Frame>,
    val tags: MutableList<Tag> = mutableListOf(),
    var header: ByteArray? = null,
    val palette: MutableList<Int> = defaultPalette().toMutableList(),
    var depth: Int = 32,
    var transparentIndex: Int = 0,
    var data: UserData? = null,
) {
    fun copyDeep() =
        Document(
            width,
            height,
            layers.map { it.copy() }.toMutableList(),
            frames
                .map { f ->
                    Frame(
                        f.duration,
                        f.cels.map { it?.copyDeep() }.toMutableList(),
                        f.metadata.toMutableList(),
                        f.palette.copyOf(),
                    )
                }
                .toMutableList(),
            tags.map { it.copy() }.toMutableList(),
            header?.copyOf(),
            palette.toMutableList(),
            depth,
            transparentIndex,
            data,
        )

    fun resolved(frame: Int, layer: Int): Cel? {
        val original = frames[frame].cels[layer] ?: return null
        var source = original
        var current = frame
        val visited = mutableSetOf<Int>()
        while (source.link != null) {
            require(visited.add(current)) { "Cyclic linked cel" }
            current = source.link!!
            require(current in frames.indices) { "Linked frame outside document" }
            source = frames[current].cels[layer] ?: error("Linked cel has no source")
        }
        if (original.link == null) return original
        return source.copy(
            x = original.x,
            y = original.y,
            opacity = original.opacity,
            link = null,
            data = original.data,
        )
    }

    fun editable(frame: Int, layer: Int): Cel {
        val c = resolved(frame, layer)
        // Keep off-canvas pixels: expanding for drawing never crops the original cel.
        val x = min(0, c?.x ?: 0)
        val y = min(0, c?.y ?: 0)
        val w = max(width, (c?.x ?: 0) + (c?.width ?: 0)) - x
        val h = max(height, (c?.y ?: 0) + (c?.height ?: 0)) - y
        require(w in 1..65535 && h in 1..65535 && w.toLong() * h <= MAX_PIXELS) {
            "This cel extends too far outside the canvas to edit safely. Resize or reposition it in Aseprite first."
        }
        val out =
            Cel(
                x,
                y,
                w,
                h,
                IntArray(w * h) { if (depth == 8) transparentIndex else 0 },
                c?.opacity ?: 255,
                data = c?.data,
            )
        if (c != null)
            for (j in 0 until c.height) for (i in 0 until c.width) out.pixels[
                    (j + c.y - y) * w + i + c.x - x] = c.pixels[j * c.width + i]
        // Detach references to this cel before altering its pixels.
        for (f in frames.indices) if (f != frame && frames[f].cels[layer]?.link != null) {
            val old = resolved(f, layer)
            if (old != null) frames[f].cels[layer] = old.copyDeep()
        }
        frames[frame].cels[layer] = out
        return out
    }

    fun display(value: Int, frame: Int, layer: Int): Int =
        if (depth != 8) value
        else if (value == transparentIndex && layers[layer].flags and 8 == 0) 0
        else frames[frame].palette.getOrElse(value) { 0 }

    fun drawingColor(color: Int, frame: Int, erase: Boolean = false): Int {
        if (erase || color ushr 24 == 0) return if (depth == 8) transparentIndex else 0
        if (depth == 16) {
            val v =
                ((color ushr 16 and 255) * 299 +
                    (color ushr 8 and 255) * 587 +
                    (color and 255) * 114 +
                    500) / 1000
            return (color and -0x1000000) or (v * 0x010101)
        }
        if (depth == 8)
            return frames[frame]
                .palette
                .indices
                .filter { it != transparentIndex }
                .minByOrNull { i ->
                    val c = frames[frame].palette[i]
                    listOf(0, 8, 16, 24).sumOf { shift ->
                        val delta = (c ushr shift and 255) - (color ushr shift and 255)
                        delta * delta
                    }
                } ?: transparentIndex
        return color
    }

    fun composite(frame: Int): IntArray {
        val out = IntArray(width * height)
        for (l in layers.indices) {
            if (!layers[l].visible) continue
            val c = resolved(frame, l) ?: continue
            val opacity = (layers[l].opacity * c.opacity + 127) / 255
            for (y in 0 until c.height) for (x in 0 until c.width) {
                val dx = x + c.x
                val dy = y + c.y
                if (dx in 0 until width && dy in 0 until height) {
                    val i = dy * width + dx
                    out[i] = over(out[i], display(c.pixels[y * c.width + x], frame, l), opacity)
                }
            }
        }
        return out
    }

    fun addFrame(after: Int, duplicate: Boolean) {
        require(frames.size < 4096)
        // Resolve links before changing frame indices.
        detachLinks()
        val f =
            if (duplicate)
                Frame(
                    frames[after].duration,
                    frames[after].cels.map { it?.copyDeep() }.toMutableList(),
                    frames[after].metadata.filter { it.first != 0x2007 }.toMutableList(),
                    frames[after].palette.copyOf(),
                )
            else
                Frame(
                    cels = MutableList(layers.size) { null },
                    palette = frames[after].palette.copyOf(),
                )
        frames.add(after + 1, f)
        tags.forEach {
            if (it.from > after) it.from++
            if (it.to > after) it.to++
        }
    }

    fun detachLinks() {
        for (f in frames.indices) for (l in layers.indices) if (frames[f].cels[l]?.link != null)
            frames[f].cels[l] = resolved(f, l)?.copyDeep()
    }

    fun removeFrame(index: Int) {
        require(frames.size > 1)
        detachLinks()
        val global = frames[0].metadata.filter { it.first == 0x2007 }
        frames.removeAt(index)
        if (index == 0) frames[0].metadata.addAll(0, global)
        tags.removeAll { it.from == index && it.to == index }
        tags.forEach {
            if (it.from > index) it.from--
            if (it.to >= index) it.to--
        }
        // Frame zero carries global palettes/profile. Keep them if deleting it.
    }

    companion object {
        const val MAX_PIXELS = 4_194_304

        fun create(w: Int = 32, h: Int = 32): Document {
            require(w in 1..2048 && h in 1..2048 && w.toLong() * h <= MAX_PIXELS)
            return Document(
                w,
                h,
                mutableListOf(Layer("Layer 1")),
                mutableListOf(Frame(cels = mutableListOf(null))),
            )
        }
    }
}

fun defaultPalette() =
    listOf(
        0xff000000.toInt(),
        0xffffffff.toInt(),
        0xff9e9e9e.toInt(),
        0xffe53935.toInt(),
        0xffff9800.toInt(),
        0xffffeb3b.toInt(),
        0xff66bb6a.toInt(),
        0xff26c6da.toInt(),
        0xff42a5f5.toInt(),
        0xff7e57c2.toInt(),
        0xffec407a.toInt(),
        0xff795548.toInt(),
    )

fun over(dst: Int, src: Int, opacity: Int = 255): Int {
    val a = ((src ushr 24) * opacity + 127) / 255
    val da = dst ushr 24
    val oa = a + (da * (255 - a) + 127) / 255
    if (oa == 0) return 0
    fun ch(s: Int): Int =
        (((src ushr s and 255) * a + (dst ushr s and 255) * da * (255 - a) / 255 + oa / 2) / oa)
            .coerceIn(0, 255)
    return (oa shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
}

enum class Tool {
    Pencil,
    Eraser,
    Fill,
    Pick,
    Line,
    Rect,
    Pan,
}

object Drawing {
    fun dot(
        c: Cel,
        x: Int,
        y: Int,
        color: Int,
        size: Int,
        canvasWidth: Int = Int.MAX_VALUE,
        canvasHeight: Int = Int.MAX_VALUE,
    ) {
        for (j in y - size / 2 until y - size / 2 + size) for (i in
            x - size / 2 until x - size / 2 + size) {
            val dx = i - c.x
            val dy = j - c.y
            if (
                i in 0 until canvasWidth &&
                    j in 0 until canvasHeight &&
                    dx in 0 until c.width &&
                    dy in 0 until c.height
            )
                c.pixels[dy * c.width + dx] = color
        }
    }

    fun line(
        c: Cel,
        x0: Int,
        y0: Int,
        x1: Int,
        y1: Int,
        color: Int,
        size: Int,
        canvasWidth: Int = Int.MAX_VALUE,
        canvasHeight: Int = Int.MAX_VALUE,
    ) {
        var x = x0
        var y = y0
        val dx = abs(x1 - x0)
        val dy = -abs(y1 - y0)
        val sx = if (x0 < x1) 1 else -1
        val sy = if (y0 < y1) 1 else -1
        var e = dx + dy
        while (true) {
            dot(c, x, y, color, size, canvasWidth, canvasHeight)
            if (x == x1 && y == y1) break
            val e2 = e * 2
            if (e2 >= dy) {
                e += dy
                x += sx
            }
            if (e2 <= dx) {
                e += dx
                y += sy
            }
        }
    }

    fun fill(
        c: Cel,
        x: Int,
        y: Int,
        color: Int,
        canvasWidth: Int = Int.MAX_VALUE,
        canvasHeight: Int = Int.MAX_VALUE,
    ) {
        val px = x - c.x
        val py = y - c.y
        if (
            x !in 0 until canvasWidth ||
                y !in 0 until canvasHeight ||
                px !in 0 until c.width ||
                py !in 0 until c.height
        )
            return
        val old = c.pixels[py * c.width + px]
        if (old == color) return
        val stack = IntArray(c.pixels.size)
        var n = 0
        val first = py * c.width + px
        stack[n++] = first
        c.pixels[first] = color
        while (n > 0) {
            val i = stack[--n]
            fun push(k: Int) {
                if (
                    c.x + k % c.width in 0 until canvasWidth &&
                        c.y + k / c.width in 0 until canvasHeight &&
                        c.pixels[k] == old
                ) {
                    c.pixels[k] = color
                    stack[n++] = k
                }
            }
            if (i % c.width > 0) push(i - 1)
            if (i % c.width < c.width - 1) push(i + 1)
            if (i >= c.width) push(i - c.width)
            if (i < c.pixels.size - c.width) push(i + c.width)
        }
    }
}

class History {
    private val undo = ArrayDeque<Document>()
    private val redo = ArrayDeque<Document>()

    private fun bytes(d: Document) =
        d.frames.sumOf { f -> f.cels.sumOf { (it?.pixels?.size ?: 0).toLong() * 4 } } + 1024

    fun push(d: Document) {
        undo.addLast(d.copyDeep())
        redo.clear()
        while (undo.size > 30 || (undo.size > 1 && undo.sumOf(::bytes) > 48L * 1024 * 1024)) undo
            .removeFirst()
    }

    fun undo(d: Document): Document? {
        if (undo.isEmpty()) return null
        redo.addLast(d.copyDeep())
        return undo.removeLast()
    }

    fun redo(d: Document): Document? {
        if (redo.isEmpty()) return null
        undo.addLast(d.copyDeep())
        return redo.removeLast()
    }

    fun clear() {
        undo.clear()
        redo.clear()
    }
}
