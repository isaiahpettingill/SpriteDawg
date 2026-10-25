package org.pocketpixel

import kotlin.math.*

/** The format-aware core stays native; Flutter owns all presentation and gestures. */
class EditorEngine {
    var document = Document.create(); private set
    var frame = 0; private set
    var layer = 0; private set
    var dirty = false; private set
    private val history = History()

    fun replace(doc: Document, unsaved: Boolean = false) {
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
        history.push(document)
        document = next; dirty = true
    }
    fun undo() { history.undo(document)?.let { document = it; dirty = true; clampSelection() } }
    fun redo() { history.redo(document)?.let { document = it; dirty = true; clampSelection() } }
    private fun clampSelection() { frame = frame.coerceIn(document.frames.indices); layer = layer.coerceIn(document.layers.indices) }
    fun stroke(args: Map<String, Any?>) {
        val tool = args["tool"] as? String ?: "pencil"
        require(tool in listOf("pencil", "eraser", "fill", "line", "rectangle", "ellipse")) { "Unknown drawing tool" }
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
        mutate { d ->
            val cel = d.editable(frame, layer)
            val value = d.drawingColor(color, frame, tool == "eraser")
            fun line(a: Pair<Int, Int>, b: Pair<Int, Int>) = Drawing.line(cel,a.first,a.second,b.first,b.second,value,size,d.width,d.height)
            val a = points.first(); val b = points.last()
            when (tool) {
                "fill" -> Drawing.fill(cel,a.first,a.second,value,d.width,d.height)
                "line" -> line(a,b)
                "rectangle" -> { val c = Pair(b.first,a.second); val e = Pair(a.first,b.second); line(a,c); line(c,b); line(b,e); line(e,a) }
                "ellipse" -> {
                    val rx = abs(b.first-a.first)/2.0; val ry = abs(b.second-a.second)/2.0
                    val cx = (a.first+b.first)/2.0; val cy = (a.second+b.second)/2.0
                    val steps = max(12, ceil(2 * PI * max(rx,ry)).toInt())
                    var prev = Pair((cx+rx).roundToInt(),cy.roundToInt())
                    for (i in 1..steps) { val t=2*PI*i/steps; val p=Pair((cx+rx*cos(t)).roundToInt(),(cy+ry*sin(t)).roundToInt()); line(prev,p); prev=p }
                }
                else -> { line(a,a); points.zipWithNext().forEach { line(it.first,it.second) } }
            }
        }
    }
    fun edit(args: Map<String, Any?>) {
        val action = args["action"] as? String ?: error("Missing edit action")
        var nextFrame = frame; var nextLayer = layer
        mutate { d -> when(action) {
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
            "addTag" -> { val from=args.number("from",frame); val to=args.number("to",frame); require(from in d.frames.indices && to in from..d.frames.lastIndex); d.tags.add(Tag(from,to,args.number("direction",0).coerceIn(0,3),0,byteArrayOf(100,100,100),args["name"] as? String ?: "Animation")) }
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
    fun state(recoveryAvailable: Boolean): Map<String, Any?> {
        val d=document
        fun rgba(p: IntArray): ByteArray = ByteArray(p.size*4).also { bytes -> p.forEachIndexed { i,c -> bytes[i*4]=(c ushr 16).toByte(); bytes[i*4+1]=(c ushr 8).toByte(); bytes[i*4+2]=c.toByte(); bytes[i*4+3]=(c ushr 24).toByte() } }
        return mapOf("width" to d.width,"height" to d.height,"frame" to frame,"layer" to layer,"depth" to d.depth,"dirty" to dirty,"canUndo" to history.canUndo,"canRedo" to history.canRedo,"recoveryAvailable" to recoveryAvailable,
            "pixels" to rgba(d.composite(frame)),"previousPixels" to if(frame>0) rgba(d.composite(frame-1)) else null,
            "palette" to (if(d.depth==8) d.frames[frame].palette.toList() else d.palette).map { it.toLong() and 0xffffffffL },
            "layers" to d.layers.map { mapOf("name" to it.name,"visible" to it.visible,"opacity" to it.opacity,"editable" to (it.flags and 2 != 0),"background" to (it.flags and 8 != 0)) },
            "frames" to d.frames.map { mapOf("duration" to it.duration) },
            "tags" to d.tags.map { mapOf("name" to it.name,"from" to it.from,"to" to it.to,"direction" to it.direction,"repeat" to it.repeat,"text" to it.data?.text) },
            "userData" to mapOf("sprite" to d.data?.text,"layer" to d.layers[layer].data?.text,"cel" to d.resolved(frame,layer)?.data?.text))
    }
}
internal fun Map<String, Any?>.number(key: String, default: Int) = (this[key] as? Number)?.toInt() ?: default
