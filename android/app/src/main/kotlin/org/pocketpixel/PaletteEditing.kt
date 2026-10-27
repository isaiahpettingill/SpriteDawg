package org.pocketpixel

/** Mutates only the EditorEngine transaction candidate. */
fun applyPaletteAction(d: Document, args: Map<String, Any?>, frame: Int) {
    fun number(key: String): Int {
        val n=args[key] as? Number ?: error("$key must be an integer")
        require(n.toDouble().isFinite() && n.toDouble()==n.toLong().toDouble() && n.toLong() in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) { "$key must be an integer" }
        return n.toInt()
    }
    fun color(): Int { val n=args["color"] as? Number ?: error("Missing RGBA color"); require(n.toDouble()==n.toLong().toDouble() && n.toLong() in 0..0xffffffffL) { "Invalid RGBA color" };return n.toInt() }
    fun name(): String { val n=args["name"] as? String ?: error("Invalid palette name");require(n.toByteArray(Charsets.UTF_8).size<=65535){"Invalid palette name"};return n }
    fun clean(f: Frame) { f.metadata.removeAll { it.first in listOf(4,17,0x2019) };f.palettePatches.clear() }
    require(frame in d.frames.indices) { "Invalid frame" }
    // Native new RGBA documents keep their swatches in the document fallback.
    d.frames.forEach { if(it.palette.isEmpty())it.palette=d.palette.toIntArray() }
    fun index(i:Int) { require(i in d.frames[frame].palette.indices){"Invalid palette index"} }
    fun uniform() { require(d.frames.all { it.palette.size==d.frames[frame].palette.size }) { "Palette sizes differ between frames. Convert to RGBA and normalize palettes externally before rearranging." } }
    fun reorder(order:List<Int>,mapping:IntArray) {
        for(f in d.frames) {
            val old=f.palette;val names=f.paletteNames.toMap();f.palette=order.map { old[it] }.toIntArray();f.paletteNames.clear();order.forEachIndexed { i,oldIndex -> names[oldIndex]?.let { f.paletteNames[i]=it } }
            if(d.depth==8)for(c in f.cels){if(c==null || c.link!=null)continue;for(p in c.pixels.indices){require(c.pixels[p] in mapping.indices){"Invalid pixel index"};c.pixels[p]=mapping[c.pixels[p]]}}
            clean(f)
        }
        if(d.depth==8)d.transparentIndex=mapping[d.transparentIndex]
    }
    when(args["action"]) {
        "palettePreset" -> {
            val values = args["colors"] as? List<*>
            require(values != null && values.size in 1..256) { "A palette preset must contain 1–256 colors" }
            val colors = values.map { value ->
                require(value is Int || value is Long) { "Invalid preset RGBA color" }
                val color = (value as Number).toLong()
                require(color in 0..0xffffffffL) { "Invalid preset RGBA color" }
                color.toInt()
            }.toMutableList()
            require(!args.containsKey("remap") || args["remap"] is Boolean) { "Remap must be a boolean" }
            if (d.depth == 8) {
                require(args["remap"] == true) { "Confirm indexed color remapping before applying a preset" }
                require(colors.size < 256) { "Indexed presets need a free transparency slot (255 colors maximum)" }
                // Check materialized size before allocating. Snapshot every linked
                // cel before changing a source, preserving per-frame palettes.
                var count = 0L
                for (f in d.frames.indices) for (l in d.layers.indices) {
                    count += d.resolved(f, l)?.pixels?.size?.toLong() ?: 0L
                    require(count <= 16777216L) { "Palette remapping would exceed decoded pixel budget" }
                }
                val resolved = d.frames.indices.map { f ->
                    d.layers.indices.map { l -> d.resolved(f, l)?.copyDeep() }
                }
                val transparent = colors.size
                fun nearest(color: Int): Int {
                    if (color ushr 24 == 0) return transparent
                    var best = 0
                    var distance = Int.MAX_VALUE
                    for (i in colors.indices) {
                        var candidate = 0
                        for (shift in listOf(0, 8, 16, 24)) {
                            val delta = (colors[i] ushr shift and 255) - (color ushr shift and 255)
                            candidate += delta * delta
                        }
                        if (candidate < distance) {
                            best = i
                            distance = candidate
                        }
                    }
                    return best
                }
                for (f in d.frames.indices) {
                    // Quantize palette entries once, not once per decoded pixel.
                    val mapping = d.frames[f].palette.map(::nearest)
                    for (l in d.layers.indices) {
                        val c = resolved[f][l]
                        if (c != null) {
                            for (p in c.pixels.indices) {
                                val value = c.pixels[p]
                                require(value in mapping.indices) { "Invalid pixel index" }
                                // Background layers display the old transparency
                                // swatch; ordinary layers use it as a hole.
                                c.pixels[p] = if (value == d.transparentIndex && d.layers[l].flags and 8 == 0)
                                    transparent else mapping[value]
                            }
                            c.link = null
                        }
                        d.frames[f].cels[l] = c
                    }
                }
                colors.add(0)
                d.transparentIndex = transparent
            }
            for (f in d.frames) {
                f.palette = colors.toIntArray()
                f.paletteNames.clear()
                clean(f)
            }
        }
        "paletteEdit" -> { val i=number("index");index(i);val c=color();val n=name();val f=d.frames[frame];f.palette[i]=c;if(n.isEmpty())f.paletteNames.remove(i) else f.paletteNames[i]=n;clean(f) }
        "paletteAdd" -> { uniform();val c=color();val n=name();require(d.frames[frame].palette.size<256){"Palette is full (256 entries)"};for(f in d.frames){val i=f.palette.size;f.palette=f.palette+c;if(n.isNotEmpty())f.paletteNames[i]=n;clean(f)} }
        "paletteMove" -> { uniform();val i=number("index");val to=number("to");index(i);index(to);val order=d.frames[frame].palette.indices.toMutableList();order.add(to,order.removeAt(i));val mapping=IntArray(order.size);order.forEachIndexed { j,v -> mapping[v]=j };reorder(order,mapping) }
        "paletteRemove" -> { uniform();val i=number("index");val replacement=number("replacement");index(i);index(replacement);require(i!=replacement && d.frames[frame].palette.size>1){"Choose another replacement swatch"};require(d.depth!=8 || (i!=d.transparentIndex && replacement!=d.transparentIndex)){"The transparent index cannot be removed or used as a replacement"};val order=d.frames[frame].palette.indices.filter { it!=i };val mapping=IntArray(order.size+1){if(it>i)it-1 else it};mapping[i]=mapping[replacement];reorder(order,mapping) }
        "convertMode" -> {
            val depth=number("depth");require(depth==8 || depth==32){"Choose indexed or RGBA"};if(depth==d.depth)return
            val countPixels=d.frames.indices.sumOf { f -> d.layers.indices.sumOf { l -> d.resolved(f,l)?.pixels?.size?.toLong() ?: 0L } };require(countPixels<=16777216L){"Conversion would exceed decoded pixel budget"}
            val resolved=d.frames.indices.map { f -> d.layers.indices.map { l -> d.resolved(f,l)?.copyDeep() } }
            if(depth==32){
                for(f in d.frames.indices)for(l in d.layers.indices){val c=resolved[f][l];if(c!=null){for(p in c.pixels.indices)c.pixels[p]=d.display(c.pixels[p],f,l);c.link=null};d.frames[f].cels[l]=c};d.depth=32
            }else{
                val count=d.frames.maxOf { it.palette.size };require(count<256){"Indexed conversion needs a free transparency slot; remove an unused swatch first"}
                for(f in d.frames){f.palette=f.palette.copyOf(count+1);clean(f)};d.transparentIndex=count;d.depth=8
                for(f in d.frames.indices)for(l in d.layers.indices){val c=resolved[f][l];if(c!=null){for(p in c.pixels.indices)c.pixels[p]=d.drawingColor(c.pixels[p],f);c.link=null};d.frames[f].cels[l]=c}
            }
        }
        else -> error("Unknown palette action ${args["action"]}")
    }
    d.palette.clear();d.palette.addAll(d.frames.first().palette.toList())
}
