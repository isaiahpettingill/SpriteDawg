package org.pocketpixel

import kotlin.math.*

/** The format-aware core stays native; Flutter owns all presentation and gestures. */
class EditorEngine {
    var document = Document.create(); private set
    var frame = 0; private set
    var layer = 0; private set
    var dirty = false; private set
    private val history = History()
    var validateCandidate: ((Document)->Unit)? = null
    var historyBudgetBytes: Long
        get() = history.budgetBytes
        set(value) { history.budgetBytes=value }

    fun replace(doc: Document, unsaved: Boolean = false) {
        validateCandidate?.invoke(doc)
        document = doc; frame = 0
        layer = doc.layers.indexOfLast { it.visible && it.flags and 2 != 0 }.coerceAtLeast(0)
        dirty = unsaved; history.clear()
    }
    fun saved() { dirty = false }
    fun select(args: Map<String, Any?>) {
        val f = args.number("frame", frame); val l = args.number("layer", layer)
        require(f in document.frames.indices && l in document.layers.indices)
        frame = f; layer = l
    }
    private fun mutate(block: (Document) -> Unit) {
        // Apply to a candidate first: errors must never half-mutate a sprite/history.
        val next = document.copyDeep()
        block(next)
        validateCandidate?.invoke(next)
        history.push(document)
        document = next; dirty = true
    }
    fun applyDocumentEdit(action: (Document) -> Unit) { mutate(action); clampSelection() }
    fun undo() { history.undo(document,validateCandidate)?.let { document = it; dirty = true; clampSelection() } }
    fun redo() { history.redo(document,validateCandidate)?.let { document = it; dirty = true; clampSelection() } }
    private fun clampSelection() { frame = frame.coerceIn(document.frames.indices); layer = layer.coerceIn(document.layers.indices) }
    fun stroke(args: Map<String, Any?>) {
        val tool = args["tool"] as? String ?: "pencil"
        require(tool in listOf("pencil", "eraser", "fill", "line", "rectangle", "ellipse", "spray", "blur", "jumble")) { "Unknown drawing tool" }
        val points = (args["points"] as? List<*>)?.map { p ->
            val a = p as List<*>; Pair((a[0] as Number).toInt(), (a[1] as Number).toInt())
        } ?: emptyList()
        if (points.isEmpty()) return
        require(points.size <= 100000) { "Stroke is too long" }
        require(points.all { abs(it.first.toLong()) <= 8192 && abs(it.second.toLong()) <= 8192 }) { "Stroke exceeds canvas limits" }
        val size = args.number("size", 1).coerceIn(1, 32)
        val color = (args["color"] as? Number)?.toLong()?.toInt() ?: 0xff000000.toInt()
        require(document.layers[layer].visible) { "Show this layer before drawing" }
        require(document.layers[layer].flags and 2 != 0) { "This layer is locked" }
        require(tool != "eraser" || document.layers[layer].flags and 8 == 0) { "Convert this background layer to transparent before erasing" }
        mutate { d -> NativeStroke.apply(d, frame, layer, args, points, size, color) }
    }
    fun edit(args: Map<String, Any?>) {
        val action = args["action"] as? String ?: error("Missing edit action")
        var nextFrame = frame; var nextLayer = layer
        mutate { d -> when(action) {
            "paletteAdd", "paletteEdit", "paletteMove", "paletteRemove", "convertMode" -> applyPaletteAction(d, args, frame)
            "addLayer" -> { require(d.layers.size < 256); d.layers.add(Layer(args["name"] as? String ?: "Layer ${d.layers.size+1}")); d.frames.forEach { it.cels.add(null) }; nextLayer=d.layers.lastIndex }
            "deleteLayer" -> { require(d.layers.size > 1) { "Keep at least one layer" }; d.layers.removeAt(layer); d.frames.forEach { it.cels.removeAt(layer) }; nextLayer=layer.coerceAtMost(d.layers.lastIndex) }
            "renameLayer" -> d.layers[layer].name = (args["name"] as String).take(1000)
            "layerVisibility" -> d.layers[layer].visible = args["visible"] as? Boolean ?: !d.layers[layer].visible
            "layerOpacity" -> d.layers[layer].opacity = args.number("opacity",255).coerceIn(0,255)
            "moveLayer" -> { val to=args.number("to",layer); require(to in d.layers.indices); d.layers.add(to,d.layers.removeAt(layer)); d.frames.forEach { it.cels.add(to,it.cels.removeAt(layer)) }; nextLayer=to }
            "transparentLayer" -> d.makeLayerTransparent(layer)
            "addFrame", "duplicateFrame" -> { d.addFrame(frame,action=="duplicateFrame"); nextFrame=frame+1 }
            "deleteFrame" -> { d.removeFrame(frame); nextFrame=frame.coerceAtMost(d.frames.lastIndex) }
            "frameDuration" -> d.frames[frame].duration=args.number("duration",100).coerceIn(1,65535)
            "addTag" -> {
                require(d.tags.size < 65535) { "Too many animation tags" }
                d.tags.add(updatedTag(Tag(frame, frame, 0, 0, byteArrayOf(100,100,100), "Animation"), args, d.frames.size))
            }
            "updateTag", "duplicateTag" -> {
                val index = args.strictInteger("index", -1)
                require(index in d.tags.indices) { "Select an existing animation tag" }
                val updated = updatedTag(d.tags[index], args, d.frames.size)
                if (action == "updateTag") d.tags[index] = updated
                else {
                    require(d.tags.size < 65535) { "Too many animation tags" }
                    d.tags.add(updated)
                }
            }
            "deleteTag" -> d.tags.removeAt(args.number("index",0))
            "userData" -> {
                val text=args["text"] as? String ?: ""; require(text.toByteArray(Charsets.UTF_8).size<=65535) { "Metadata exceeds 65535 UTF-8 bytes" }
                fun changed(old: UserData?) = (old ?: UserData()).copy(text=text)
                when(args["target"]) {
                    "sprite" -> d.data=changed(d.data)
                    "layer" -> d.layers[layer].data=changed(d.layers[layer].data)
                    "cel" -> { val c=d.editable(frame,layer); c.data=changed(c.data) }
                    "tag" -> { val t=d.tags[args.number("index",0)]; t.data=changed(t.data) }
                    else -> error("Unknown metadata target")
                }
            }
            "resize" -> { val w=args.number("width",d.width); val h=args.number("height",d.height); require(w in 1..2048 && h in 1..2048 && w.toLong()*h<=Document.MAX_PIXELS); d.width=w; d.height=h }
            "flipHorizontal", "flipVertical" -> { val c=d.editable(frame,layer); val old=c.pixels.copyOf(); for(y in 0 until d.height) for(x in 0 until d.width) { val sx=if(action=="flipHorizontal") d.width-1-x else x; val sy=if(action=="flipVertical") d.height-1-y else y; c.pixels[(y-c.y)*c.width+x-c.x]=old[(sy-c.y)*c.width+sx-c.x] } }
            else -> error("Unknown edit action: $action")
        } }
        frame=nextFrame; layer=nextLayer
    }
    private fun updatedTag(original: Tag, args: Map<String, Any?>, frameCount: Int): Tag {
        val from = args.strictInteger("from", original.from)
        val to = args.strictInteger("to", original.to)
        val direction = args.strictInteger("direction", original.direction)
        val repeat = args.strictInteger("repeat", original.repeat)
        val name = if (args.containsKey("name")) args["name"] else original.name
        require(name is String && name.toByteArray(Charsets.UTF_8).size <= 65535) { "Tag name must fit 65535 UTF-8 bytes" }
        require(from >= 0 && from <= to && to < frameCount) { "Select a contiguous frame range inside the sprite" }
        require(direction in 0..3) { "Tag direction must be from 0 to 3" }
        require(repeat in 0..65535) { "Tag repeat must be from 0 to 65535" }
        // Preserve unedited metadata, but do not alias mutable bytes between copies.
        return original.copy(from = from, to = to, direction = direction, repeat = repeat,
            name = name, color = original.color.copyOf(),
            data = original.data?.let { it.copy(properties = it.properties?.copyOf()) })
    }

    fun thumbnails(args: Map<String, Any?>): Map<String, Any?> {
        val requested = args["frames"] as? List<*> ?: error("Provide a list of frame indices")
        require(requested.size <= 32) { "Request at most 32 thumbnails at a time" }
        val maxSize = args.strictInteger("maxSize", 48)
        require(maxSize > 0) { "Thumbnail size must be positive" }
        val bound = min(maxSize, 64)
        val d = document
        val frames = requested.map { value ->
            require(value is Number && value.toDouble() == value.toInt().toDouble()) { "Frame index must be an integer" }
            value.toInt().also { require(it in d.frames.indices) { "Frame index is outside the sprite" } }
        }
        val scale = min(1.0, bound.toDouble() / max(d.width, d.height))
        val width = max(1, (d.width * scale).roundToInt())
        val height = max(1, (d.height * scale).roundToInt())
        val images = frames.map { index ->
            val rgba = IntArray(width * height)
            for (layerIndex in d.layers.indices) {
                val info = d.layers[layerIndex]
                if (!info.visible) continue
                val cel = d.resolved(index, layerIndex) ?: continue
                val opacity = (info.opacity * cel.opacity + 127) / 255
                for (y in 0 until height) for (x in 0 until width) {
                    val sx = x * d.width / width - cel.x; val sy = y * d.height / height - cel.y
                    if (sx in 0 until cel.width && sy in 0 until cel.height) {
                        val i = y * width + x
                        rgba[i] = over(rgba[i], d.display(cel.pixels[sy * cel.width + sx], index, layerIndex), opacity)
                    }
                }
            }
            val pixels = ByteArray(width * height * 4)
            rgba.forEachIndexed { i, color ->
                pixels[i*4] = (color ushr 16).toByte(); pixels[i*4+1] = (color ushr 8).toByte()
                pixels[i*4+2] = color.toByte(); pixels[i*4+3] = (color ushr 24).toByte()
            }
            mapOf("frame" to index, "width" to width, "height" to height, "pixels" to pixels)
        }
        return mapOf("thumbnails" to images)
    }

    fun state(recoveryAvailable: Boolean): Map<String, Any?> {
        val d=document
        fun rgba(p: IntArray): ByteArray = ByteArray(p.size*4).also { bytes -> p.forEachIndexed { i,c -> bytes[i*4]=(c ushr 16).toByte(); bytes[i*4+1]=(c ushr 8).toByte(); bytes[i*4+2]=c.toByte(); bytes[i*4+3]=(c ushr 24).toByte() } }
        return mapOf("width" to d.width,"height" to d.height,"frame" to frame,"layer" to layer,"depth" to d.depth,"dirty" to dirty,"canUndo" to history.canUndo,"canRedo" to history.canRedo,"recoveryAvailable" to recoveryAvailable,
            "pixels" to rgba(d.composite(frame)),"previousPixels" to if(frame>0) rgba(d.composite(frame-1)) else null,
            "palette" to (if(d.frames[frame].palette.isNotEmpty()) d.frames[frame].palette.toList() else d.palette).map { it.toLong() and 0xffffffffL },
            "transparentIndex" to d.transparentIndex,
            "paletteNames" to (if(d.frames[frame].palette.isNotEmpty()) d.frames[frame].palette.indices else d.palette.indices).map { d.frames[frame].paletteNames[it] ?: "" },
            "layers" to d.layers.map { mapOf("name" to it.name,"visible" to it.visible,"opacity" to it.opacity,"editable" to (it.flags and 2 != 0),"background" to (it.flags and 8 != 0)) },
            "frames" to d.frames.map { mapOf("duration" to it.duration) },
            "tags" to d.tags.map { mapOf("name" to it.name,"from" to it.from,"to" to it.to,"direction" to it.direction,"repeat" to it.repeat,"text" to it.data?.text) },
            "userData" to mapOf("sprite" to d.data?.text,"layer" to d.layers[layer].data?.text,"cel" to d.resolved(frame,layer)?.data?.text))
    }
}
internal fun Map<String, Any?>.number(key: String, default: Int) = (this[key] as? Number)?.toInt() ?: default

internal fun Map<String, Any?>.strictInteger(key: String, default: Int): Int {
    if (!containsKey(key)) return default
    val value = this[key]
    require(value is Number && value.toDouble() == value.toInt().toDouble()) { "$key must be an integer" }
    return value.toInt()
}
