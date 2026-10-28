package org.pocketpixel

import kotlin.math.*

/** Native pixel operations. Ordinary ink covers once; spray/airbrush accumulate per dab. */
internal object NativeStroke {
    fun prepareSplatterPixels(d: Document, frame: Int, layer: Int, args: Map<String,Any?>, points: List<Pair<Int,Int>>, size: Int, color: Int): Map<Int,Int> {
        val selected = if (args.containsKey("paletteIndex")) args.strictInteger("paletteIndex", -1) else null
        if (d.depth == 8 && selected != null) require(selected in d.frames[frame].palette.indices) { "Invalid palette index" }
        if (color ushr 24 == 0) return emptyMap()
        val index = if (d.depth == 8) selected ?: d.drawingColor(color, frame) else null
        if (index != null && d.display(index, frame, layer) ushr 24 == 0) return emptyMap()
        val pixels = splatterPixels(points, d.width, d.height, size,
            (args["seed"] as? Number)?.toLong() ?: 1L, args["mirrorX"] == true, args["mirrorY"] == true,
            args["mirrorDiagonal"] == true, args["mirrorAntiDiagonal"] == true, args["wrap"] == true)
        val changes = linkedMapOf<Int,Int>()
        val cel = d.resolved(frame, layer)
        for ((position, coverage) in pixels) {
            val x = position % d.width; val y = position / d.width
            val original = if (cel != null && x >= cel.x && x < cel.x+cel.width && y >= cel.y && y < cel.y+cel.height)
                cel.pixels[(y-cel.y)*cel.width+x-cel.x] else if (d.depth == 8) d.transparentIndex else 0
            val alpha = ((color ushr 24)*coverage+127)/255
            if (index == null && alpha == 0) continue
            val ink = (color and 0xffffff) or (alpha shl 24)
            val value = index ?: d.drawingColor(over(original, ink), frame)
            if (value != original) changes[position] = value
        }
        return changes
    }
    fun preparePalettePixels(d: Document, frame: Int, layer: Int, args: Map<String, Any?>, points: List<Pair<Int,Int>>, size: Int, color: Int): Map<Int,Int> {
        val tool = args["tool"] as? String ?: "pencil"
        val palette = d.frames[frame].palette
        val selected = if (args.containsKey("paletteIndex")) args.strictInteger("paletteIndex", -1) else null
        if (selected != null) require(selected in palette.indices) { "Invalid palette index" }
        val excluded = if (d.depth == 8 && d.layers[layer].flags and 8 == 0) d.transparentIndex else null
        val dithering = tool == "ditherPaint" || tool == "ditherRetouch"
        if (!dithering && selected != null && selected == excluded) return emptyMap()
        val ramp = if (dithering) listOf(0,0,0,0,0) else paletteShadeRamp(palette, color, selected, excluded)
        val pixels = paletteTexturePixels(tool, points, d.width, d.height, size, ramp,
            (args["seed"] as? Number)?.toLong() ?: 1L, args["mirrorX"] == true, args["mirrorY"] == true,
            args["mirrorDiagonal"] == true, args["mirrorAntiDiagonal"] == true, args["wrap"] == true)
        val cache = mutableMapOf<Long, Int>()
        val strength = args.strictInteger("strength", 50).coerceIn(1, 100)
        val changes = linkedMapOf<Int,Int>()
        val cel = d.resolved(frame, layer)
        for ((position, entry) in pixels) {
            val x = position % d.width; val y = position / d.width
            val raw = if (cel != null && x >= cel.x && x < cel.x+cel.width && y >= cel.y && y < cel.y+cel.height)
                cel.pixels[(y-cel.y)*cel.width+x-cel.x] else if (d.depth == 8) d.transparentIndex else 0
            val source = d.display(raw, frame, layer)
            val paletteEntry = if (dithering) {
                val key = ((source.toLong() and 0xffffffffL) shl 4) or ((y and 3)*4+(x and 3)).toLong()
                cache.getOrPut(key) {
                    if (tool == "ditherRetouch") retouchPaletteIndex(palette, source, x, y, excluded)
                    else ditherPaletteIndex(palette, source, color, x, y, strength, excluded)
                }
            } else entry
            if (paletteEntry !in palette.indices) continue
            val ink = if (paletteEntry == excluded) 0 else palette[paletteEntry]
            if (tool == "ditherRetouch" && ink == source) continue
            val replacement = if (d.depth == 8) paletteEntry
                else d.drawingColor(if (dithering) ink else over(source, ink), frame)
            if (replacement != raw) changes[position] = replacement
        }
        return changes

    }
    fun apply(d: Document, frame: Int, layer: Int, args: Map<String, Any?>, points: List<Pair<Int,Int>>, size: Int, color: Int, preparedPixels: Map<Int,Int>? = null) {
        val tool = args["tool"] as? String ?: "pencil"
        if (tool in paletteTextureTools || tool == "splatter") {
            val changes = preparedPixels ?: if (tool == "splatter") prepareSplatterPixels(d, frame, layer, args, points, size, color)
                else preparePalettePixels(d, frame, layer, args, points, size, color)
            if (changes.isEmpty()) return
            val cel = d.editable(frame,layer)
            for ((position, value) in changes) {
                val x = position % d.width; val y = position / d.width
                cel.pixels[(y-cel.y)*cel.width+x-cel.x] = value
            }
            return
        }
        val cel = d.editable(frame,layer)
        val effect = tool == "blur" || tool == "jumble"
        val source = if (effect || tool == "fill") cel.pixels.copyOf() else cel.pixels
        val paletteIndex = if (args.containsKey("paletteIndex")) args.strictInteger("paletteIndex", -1) else null
        if (d.depth == 8 && paletteIndex != null) require(paletteIndex in d.frames[frame].palette.indices) { "Invalid palette index" }
        val value = if (d.depth == 8 && paletteIndex != null && tool != "eraser" && tool != "gradient" && tool != "blur" && !(tool == "fill" && args["gradient"] == true)) paletteIndex
            else d.drawingColor(color,frame,tool=="eraser")
        val wrap=args["wrap"] == true
        val symmetry=StrokeSymmetry(d.width,d.height,args["mirrorX"] == true,args["mirrorY"] == true,
            args["mirrorDiagonal"] == true,args["mirrorAntiDiagonal"] == true,wrap)
        val mask = linkedSetOf<Int>()
        val painted = mutableSetOf<Int>()
        val accumulates = tool == "spray" || tool == "airbrush"
        fun paint(i: Int, ink: Int) {
            if (!accumulates && !painted.add(i)) return
            cel.pixels[i] = if (tool == "eraser" || d.depth == 8) ink else over(cel.pixels[i], ink)
        }
        var randomState = ((args["seed"] as? Number)?.toLong() ?: 1L) and 0xffffffffL
        fun next(): Long { randomState=(randomState*1664525L+1013904223L) and 0xffffffffL; return randomState ushr 16 }
        fun index(x: Int,y: Int) = (y-cel.y)*cel.width+x-cel.x
        fun pixel(x: Int,y: Int, ink: Int = value, stamp: MutableSet<Int>? = null) {
            for((px,py) in symmetry.points(x,y)) {
                val i=index(px,py)
                if(stamp != null && !stamp.add(i)) continue
                if(effect) mask.add(i) else paint(i,ink)
            }
        }
        fun dot(x: Int,y: Int) {
            for(py in y-size/2 until y-size/2+size) for(px in x-size/2 until x-size/2+size) pixel(px,py)
        }
        fun line(a: Pair<Int,Int>,b: Pair<Int,Int>,skipFirst: Boolean=false, stamp: (Int,Int)->Unit = ::dot) {
            var x=a.first;var y=a.second
            val dx=abs(b.first-x);val dy=-abs(b.second-y);val sx=if(x<b.first) 1 else -1;val sy=if(y<b.second) 1 else -1
            var error=dx+dy;var first=true
            while(true) {
                if(!first || !skipFirst) stamp(x,y)
                first=false
                if(x==b.first && y==b.second) break
                val twice=error*2
                if(twice>=dy) { error+=dy;x+=sx }
                if(twice<=dx) { error+=dx;y+=sy }
            }
        }
        val a=points.first();val b=points.last()
        if(tool=="gradient") {
            // Canvas-wide linear field: size and mirror settings do not apply.
            val dx=(b.first-a.first).toLong();val dy=(b.second-a.second).toLong()
            val originX=if(wrap) Math.floorMod(a.first,d.width) else a.first
            val originY=if(wrap) Math.floorMod(a.second,d.height) else a.second
            val denominator=dx*dx+dy*dy
            if(denominator==0L) return
            val second=(args["secondaryColor"] as? Number)?.toLong()?.toInt() ?: color
            for(y in 0 until d.height) for(x in 0 until d.width) {
                val position=((x-originX)*dx+(y-originY)*dy).coerceIn(0L,denominator)
                var ink=0
                for(shift in listOf(0,8,16,24)) {
                    val from=color ushr shift and 255;val to=second ushr shift and 255
                    val channel=(from*(denominator-position)+to*position+denominator/2)/denominator
                    ink=ink or (channel.toInt() shl shift)
                }
                if(ink ushr 24==0) continue
                val i=index(x,y)
                cel.pixels[i]=d.drawingColor(over(d.display(cel.pixels[i],frame,layer),ink),frame)
            }
            return
        }
        if(tool=="fill") {
            val gradient=args["gradient"]==true
            val second=(args["secondaryColor"] as? Number)?.toLong()?.toInt() ?: color
            val direction=args["gradientDirection"] as? String ?: "vertical"
            require(!gradient || direction in listOf("horizontal","vertical")) { "Gradient direction must be horizontal or vertical" }
            // Transform the gradient vector as well as its seed: diagonals swap
            // horizontal/vertical directions rather than merely reversing them.
            val seeds=symmetry.transforms.map { t ->
                val point=symmetry.transformedPoint(t,a.first,a.second)
                val vector=t.vector(if(direction=="horizontal") 1 else 0,if(direction=="vertical") 1 else 0)
                Triple(point,vector.first != 0,vector.first+vector.second < 0)
            }
            val visited=BooleanArray(source.size);val region=IntArray(source.size)
            for((point,horizontal,reverse) in seeds) {
                val (sx,sy)=point
                if(sx !in 0 until d.width || sy !in 0 until d.height || visited[index(sx,sy)]) continue
                val target=source[index(sx,sy)];var count=0;var head=0
                var left=sx;var right=sx;var top=sy;var bottom=sy
                fun queue(x: Int,y: Int) {
                    val xx=if(wrap) Math.floorMod(x,d.width) else x
                    val yy=if(wrap) Math.floorMod(y,d.height) else y
                    if(xx !in 0 until d.width || yy !in 0 until d.height) return
                    val i=index(xx,yy)
                    if(!visited[i] && source[i]==target) { visited[i]=true;region[count++]=i }
                }
                queue(sx,sy)
                while(head<count) {
                    val i=region[head++];val x=i%cel.width+cel.x;val y=i/cel.width+cel.y
                    left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
                    queue(x-1,y);queue(x+1,y);queue(x,y-1);queue(x,y+1)
                }
                val start=if(horizontal) left else top
                val end=if(horizontal) right else bottom
                val den=end-start
                for(n in 0 until count) {
                    val i=region[n]
                    if(!gradient) { paint(i,value);continue }
                    var position=(if(horizontal) i%cel.width+cel.x else i/cel.width+cel.y)-start
                    if(reverse) position=den-position
                    var mixed=0
                    for(shift in listOf(0,8,16,24)) {
                        val ca=color ushr shift and 255;val cb=second ushr shift and 255
                        val channel=if(den==0) ca else (ca*(den-position)+cb*position+den/2)/den
                        mixed=mixed or (channel shl shift)
                    }
                    paint(i,d.drawingColor(mixed,frame))
                }
            }
            return
        }
        when(tool) {
            "line" -> line(a,b)
            "rectangle", "ellipse" -> {
                val left=min(a.first,b.first);val right=max(a.first,b.first)
                val top=min(a.second,b.second);val bottom=max(a.second,b.second)
                if(args["filled"]==true) {
                    val w=(right-left+1).toLong();val h=(bottom-top+1).toLong()
                    val bounds=symmetry.sourceBounds
                    val minX=if(wrap) 0 else max(bounds.left,left)
                    val maxX=if(wrap) d.width-1 else min(bounds.right,right)
                    val minY=if(wrap) 0 else max(bounds.top,top)
                    val maxY=if(wrap) d.height-1 else min(bounds.bottom,bottom)
                    for(y in minY..maxY) for(x in minX..maxX) {
                        val sx=if(wrap) periodicRepresentative(left,right,x,d.width) ?: continue else x
                        val sy=if(wrap) periodicRepresentative(top,bottom,y,d.height) ?: continue else y
                        val nx=2L*sx-left-right;val ny=2L*sy-top-bottom
                        if(tool=="rectangle" || nx*nx*h*h+ny*ny*w*w<=w*w*h*h) pixel(x,y)
                    }
                } else if(tool=="rectangle") {
                    val c=Pair(b.first,a.second);val e=Pair(a.first,b.second)
                    line(a,c);line(c,b);line(b,e);line(e,a)
                } else {
                    val rx=abs(b.first-a.first)/2.0;val ry=abs(b.second-a.second)/2.0
                    val cx=(a.first+b.first)/2.0;val cy=(a.second+b.second)/2.0
                    val steps=max(12,ceil(2*PI*max(rx,ry)).toInt())
                    // Dart rounds half-pixels away from zero; Kotlin's default
                    // rounds negative halves toward positive infinity. Keep the
                    // original-coordinate outline identical before reflection.
                    fun rasterRound(v: Double) = if(v < 0) -(-v).roundToInt() else v.roundToInt()
                    var previous=Pair(rasterRound(cx+rx),rasterRound(cy))
                    for(i in 1..steps) { val t=2*PI*i/steps;val p=Pair(rasterRound(cx+rx*cos(t)),rasterRound(cy+ry*sin(t)));line(previous,p);previous=p }
                }
            }
            "airbrush" -> {
                val strength=args.strictInteger("strength",50).coerceIn(1,100)
                fun airbrush(x: Int,y: Int) {
                    val stamp=mutableSetOf<Int>()
                    val radiusSquared=size*size
                    for(oy in 0 until size) for(ox in 0 until size) {
                        val dx=2*ox-size+1;val dy=2*oy-size+1
                        val distance=dx*dx+dy*dy
                        if(distance>=radiusSquared) continue
                        val alpha=((color ushr 24)*strength*(radiusSquared-distance)+radiusSquared*50)/(radiusSquared*100)
                        if(alpha==0) continue
                        val ink=(color and 0xffffff) or (alpha shl 24)
                        val px=x-size/2+ox;val py=y-size/2+oy
                        if(d.depth==8) {
                            for((xx,yy) in symmetry.points(px,py)) {
                                val i=index(xx,yy)
                                if(!stamp.add(i)) continue
                                cel.pixels[i]=d.drawingColor(over(d.display(cel.pixels[i],frame,layer),ink),frame)
                            }
                        } else pixel(px,py,d.drawingColor(ink,frame),stamp)
                    }
                }
                airbrush(a.first,a.second)
                points.zipWithNext().forEach { if(it.first==it.second) airbrush(it.second.first,it.second.second) else line(it.first,it.second,true,::airbrush) }
            }
            "spray" -> {
                val density=args.strictInteger("density",12).coerceIn(1,100)
                fun spray(x: Int,y: Int) {
                    repeat(density) {
                        val ox=(next()%size).toInt();val oy=(next()%size).toInt()
                        val nx=2*ox-size+1;val ny=2*oy-size+1
                        if(nx*nx+ny*ny<=size*size) pixel(x-size/2+ox,y-size/2+oy)
                    }
                }
                spray(a.first,a.second)
                points.zipWithNext().forEach { if(it.first==it.second) spray(it.second.first,it.second.second) else line(it.first,it.second,true,::spray) }
            }
            else -> { dot(a.first,a.second);points.zipWithNext().forEach { line(it.first,it.second,true) } }
        }
        if(tool=="blur" || tool=="jumble") {
            val strength=args.strictInteger("strength",50).coerceIn(1,100)
            if(tool=="jumble") {
                // Local swaps make even a one-pixel brush useful and preserve
                // native palette indices, transparent pixels and the histogram.
                for(i in mask) {
                    if(next()%100>=strength) continue
                    val x=i%cel.width+cel.x;val y=i/cel.width+cel.y
                    val neighbours=mutableListOf<Int>()
                    val minX=if(wrap) x-1 else max(0,x-1);val maxX=if(wrap) x+1 else min(d.width-1,x+1)
                    val minY=if(wrap) y-1 else max(0,y-1);val maxY=if(wrap) y+1 else min(d.height-1,y+1)
                    for(yy in minY..maxY) for(xx in minX..maxX) {
                        val j=index(if(wrap) Math.floorMod(xx,d.width) else xx,if(wrap) Math.floorMod(yy,d.height) else yy)
                        if(j!=i && cel.pixels[j]!=cel.pixels[i] && j !in neighbours) neighbours.add(j)
                    }
                    if(neighbours.isEmpty()) continue
                    val j=neighbours[(next()%neighbours.size).toInt()];val old=cel.pixels[i]
                    cel.pixels[i]=cel.pixels[j];cel.pixels[j]=old
                }
            } else for(i in mask) {
                val x=i%cel.width+cel.x;val y=i/cel.width+cel.y
                var count=0;var alpha=0;val sums=LongArray(3)
                val minX=if(wrap) x-1 else max(0,x-1);val maxX=if(wrap) x+1 else min(d.width-1,x+1)
                val minY=if(wrap) y-1 else max(0,y-1);val maxY=if(wrap) y+1 else min(d.height-1,y+1)
                for(py in minY..maxY) for(px in minX..maxX) {
                    val sx=if(wrap) Math.floorMod(px,d.width) else px
                    val sy=if(wrap) Math.floorMod(py,d.height) else py
                    val c=d.display(source[index(sx,sy)],frame,layer);val ca=c ushr 24
                    alpha+=ca;count++
                    for(channel in 0..2) sums[channel]+=(c ushr (16-channel*8) and 255).toLong()*ca
                }
                val averagedAlpha=(alpha+count/2)/count
                val current=d.display(source[i],frame,layer);val ca=current ushr 24
                val totalAlpha=ca*(100-strength)+averagedAlpha*strength
                var mixed=((totalAlpha+50)/100) shl 24
                for(channel in 0..2) {
                    val averaged=if(alpha==0) 0 else ((sums[channel]+alpha/2)/alpha).toInt()
                    val original=current ushr (16-channel*8) and 255
                    val c=if(totalAlpha==0) 0 else (original.toLong()*ca*(100-strength)+averaged.toLong()*averagedAlpha*strength+totalAlpha/2)/totalAlpha
                    mixed=mixed or (c.toInt() shl (16-channel*8))
                }
                cel.pixels[i]=d.drawingColor(mixed,frame)
            }
        }
    }
}
