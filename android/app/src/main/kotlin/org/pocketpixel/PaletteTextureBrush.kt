package org.pocketpixel

import kotlin.math.*

internal val paletteTextureTools = setOf("metal", "cluster", "stripes", "sphere", "knife", "bark", "ditherPaint", "ditherRetouch")

/** Oklab matrices from Björn Ottosson's public-domain reference (2021-01-25). */
internal class PaletteLab(argb: Int) {
    val l: Double; val a: Double; val b: Double; val alpha: Double
    init {
        fun linear(shift: Int): Double {
            val c = (argb ushr shift and 255) / 255.0
            return if (c <= .04045) c / 12.92 else ((c + .055) / 1.055).pow(2.4)
        }
        val r = linear(16); val g = linear(8); val blue = linear(0)
        val x = (.4122214708*r + .5363325363*g + .0514459929*blue).pow(1.0/3)
        val y = (.2119034982*r + .6806995451*g + .1073969566*blue).pow(1.0/3)
        val z = (.0883024619*r + .2817188376*g + .6299787005*blue).pow(1.0/3)
        l = .2104542553*x + .7936177850*y - .0040720468*z
        a = 1.9779984951*x - 2.4285922050*y + .4505937099*z
        b = .0259040371*x + .7827717662*y - .8086757660*z
        alpha = (argb ushr 24) / 255.0
    }
}

internal fun paletteShadeRamp(palette: IntArray, color: Int, selectedIndex: Int? = null, transparentIndex: Int? = null): List<Int> {
    if (palette.isEmpty()) return emptyList()
    val labs = palette.map(::PaletteLab); val chosen = PaletteLab(color)
    val usable = palette.indices.filter { it != transparentIndex && labs[it].alpha > 0 }
    if (usable.isEmpty() || chosen.alpha == 0.0) return emptyList()
    fun sq(x: Double) = x*x
    fun distance(p: PaletteLab,q: PaletteLab) = sq(p.l-q.l)+sq(p.a-q.a)+sq(p.b-q.b)+.5*sq(p.alpha-q.alpha)
    var anchor = usable.first()
    for(i in usable) if(distance(labs[i],chosen)<distance(labs[anchor],chosen)) anchor=i
    if(selectedIndex != null && selectedIndex in usable) anchor=selectedIndex
    val base = labs[anchor]
    val candidates = usable.filter { i ->
        val p=labs[i]
        abs(p.alpha-base.alpha)<=.08 && sqrt(sq(p.a-base.a)+sq(p.b-base.b))<=.16
    }
    return listOf(-.24,-.12,0.0,.12,.24).map { offset ->
        var best=anchor; var bestScore=Double.POSITIVE_INFINITY
        for(i in candidates) {
            val p=labs[i]
            if(offset<0 && p.l>base.l+.000001 || offset>0 && p.l<base.l-.000001) continue
            val score=sq(p.l-(base.l+offset).coerceIn(0.0,1.0))+2.0*(sq(p.a-base.a)+sq(p.b-base.b))+.5*sq(p.alpha-base.alpha)
            if(score<bestScore-1e-12 || abs(score-bestScore)<=1e-12 && i==anchor) {best=i;bestScore=score}
        }
        if(offset==0.0) anchor else best
    }
}

/** Same integer resampling, palette indices and deterministic texture as Dart. */
internal fun paletteTexturePixels(tool: String, points: List<Pair<Int,Int>>, width: Int, height: Int, size: Int, ramp: List<Int>, seed: Long=1L, mirrorX: Boolean=false, mirrorY: Boolean=false): Map<Int,Int> {
    val out=linkedMapOf<Int,Int>()
    if(points.isEmpty() || ramp.isEmpty()) return out
    val p=mutableListOf<Pair<Int,Int>>()
    for(point in points) {
        if(p.lastOrNull()==point) continue
        while(p.size>=2) {
            val a=p[p.size-2]; val b=p.last()
            val dx=b.first-a.first;val dy=b.second-a.second;val ex=point.first-b.first;val ey=point.second-b.second
            if(dx.toLong()*ey-dy.toLong()*ex!=0L || dx.toLong()*ex+dy.toLong()*ey<=0L) break
            p.removeAt(p.lastIndex)
        }
        p.add(point)
    }
    fun hash(x: Int,y: Int): Long {
        var v=(x.toLong()*374761393+y.toLong()*668265263+(seed and 0xffffffffL)*69069) and 0xffffffffL
        v=((v xor (v ushr 13))*1274126177) and 0xffffffffL
        return (v xor (v ushr 16)) and 0x7fffffffL
    }
    fun cluster(x: Double,y: Double,cell: Double): Int {
        val gx=floor(x/cell).toInt();val gy=floor(y/cell).toInt()
        var best=Double.POSITIVE_INFINITY;var shade=2
        for(cy in gy-1..gy+1) for(cx in gx-1..gx+1) {
            val h=hash(cx,cy)
            val px=(cx+.2+(h%601)/1000.0)*cell;val py=(cy+.2+((h ushr 10)%601)/1000.0)*cell
            val d=(x-px)*(x-px)+(y-py)*(y-py)
            if(d<best) {best=d;shade=((h ushr 20)%5).toInt()}
        }
        return shade
    }
    // Canvas-anchored vertical grain. The seed changes the tree, not each dab;
    // overlapping stamps and live-preview extensions sample the same field.
    fun bark(x: Int, y: Int): Int {
        val cell = max(2.0, size / 5.0)
        var u = x / cell
        val v = y / cell
        val knotColumn = floor(u / 6).toInt(); val knotRow = floor(v / 18).toInt()
        for (ky in knotRow - 1..knotRow + 1) {
            for (kx in knotColumn - 1..knotColumn + 1) {
                val h = hash(kx + 1709, ky - 313)
                if (h % 3 != 0L) continue
                val cx = kx * 6 + 1.5 + ((h ushr 3) % 301) / 100.0
                val cy = ky * 18 + 4 + ((h ushr 12) % 1001) / 100.0
                val dx = u - cx; val dy = (v - cy) / 2.8
                val radius = sqrt(dx * dx + dy * dy)
                if (radius < .24) return 0
                if (radius < .43) return 1
                if (radius < .62) return 3
                if (radius < .77) return 0
                if (radius < .95) return if (dx < 0) 3 else 2
                // Deflect nearby grain around the elongated knot.
                if (radius < 2.2) {
                    u += (if (dx < 0) -1 else 1) * (2.2 - radius) * .38
                }
            }
        }
        val lane = floor(u).toInt(); val segment = floor(v / 7).toInt()
        val t = v / 7 - segment; val smooth = t * t * (3 - 2 * t)
        var distance = Double.POSITIVE_INFINITY; var side = 0.0; var nearest = lane
        for (i in lane - 2..lane + 2) {
            val start = (hash(i, segment) % 1001) / 1000.0
            val end = (hash(i, segment + 1) % 1001) / 1000.0
            val center = i + .15 + .7 * (start + (end - start) * smooth)
            val delta = u - center
            if (abs(delta) < distance) {
                distance = abs(delta)
                side = delta
                nearest = i
            }
        }
        if (distance < .10) return 0
        if (distance < .23) return 1
        if (side > 0 && distance < .34) return 4
        if (side > 0 && distance < .49) return 3
        // Short connected fissures, not independent random bright pixels.
        val crack = v / 3 + (hash(nearest, 911) % 100) / 100.0
        if (crack - floor(crack) < .09 && hash(nearest, floor(crack).toInt()) % 4 == 0L) return 1
        return 2
    }
    fun emit(x: Int,y: Int,shade: Int) {
        val xs=linkedSetOf(x); val ys=linkedSetOf(y)
        if(mirrorX) xs.add(width-1-x)
        if(mirrorY) ys.add(height-1-y)
        for(xx in xs) for(yy in ys) if(xx in 0 until width && yy in 0 until height) out[yy*width+xx]=ramp[shade.coerceIn(0,4)]
    }
    val clusterCache = mutableMapOf<Int,Int>()
    val barkCache = mutableMapOf<Int,Int>()
    fun stamp(x: Int,y: Int,tx: Double,ty: Double) {
        val left = x-size/2; val top = y-size/2
        if (left >= width || top >= height || left+size <= 0 || top+size <= 0) return
        val cell=max(2.0,size/3.0)
        for(oy in 0 until size) for(ox in 0 until size) {
            val px=left+ox; val py=top+oy
            if (px !in 0 until width || py !in 0 until height) continue
            val nx=(2*ox-size+1).toDouble()/size;val ny=(2*oy-size+1).toDouble()/size
            val radius=nx*nx+ny*ny
            if(radius>1) continue
            val shade=when(tool) {
                "ditherPaint", "ditherRetouch" -> 2
                "cluster" -> clusterCache.getOrPut(py*width+px) { cluster(px.toDouble(),py.toDouble(),cell) }
                "bark" -> barkCache.getOrPut(py*width+px) { bark(px, py) }
                "stripes" -> cluster((px*tx+py*ty)/4,-px*ty+py*tx,cell)
                "sphere" -> {
                    val light=(.62*sqrt(max(0.0,1-radius))-.70*ny-.18*nx).coerceIn(-1.0,1.0)
                    ((light+1)*2).roundToInt()
                }
                "knife" -> {
                    val normal=-nx*ty+ny*tx
                    if(normal<-.45) 4 else if(normal<0) 3 else if(normal<.5) 1 else 0
                }
                else -> {
                    val normal=-nx*ty+ny*tx
                    if(normal<-.65) 1 else if(normal<-.25) 3 else if(normal<-.05) 4 else if(normal<.3) 0 else if(normal<.65) 2 else 1
                }
            }
            emit(px,py,shade)
        }
    }
    if(p.size==1) {stamp(p.first().first,p.first().second,1.0,0.0);return out}
    for(j in 1 until p.size) {
        val from=p[j-1];val to=p[j]
        val vx=to.first-from.first;val vy=to.second-from.second;val length=sqrt((vx.toLong()*vx+vy.toLong()*vy).toDouble())
        val tx=vx/length;val ty=vy/length
        var x=from.first;var y=from.second;var e=abs(vx)-abs(vy)
        val dx=abs(vx);val dy=-abs(vy);val sx=if(vx>0) 1 else -1;val sy=if(vy>0) 1 else -1
        while(true) {
            stamp(x,y,tx,ty)
            if(x==to.first && y==to.second) break
            val twice=e*2
            if(twice>=dy) {e+=dy;x+=sx}
            if(twice<=dx) {e+=dx;y+=sy}
        }
    }
    return out
}

/** Ordered palette interpolation against the immutable pre-stroke background. */
internal fun ditherPaletteIndex(palette: IntArray, background: Int, foreground: Int, x: Int, y: Int, strength: Int, transparentIndex: Int? = null): Int {
    if(palette.isEmpty()) return 0
    val bg=PaletteLab(if(background ushr 24==0) foreground and 0xffffff else background)
    val fg=PaletteLab(foreground)
    val delta=doubleArrayOf(fg.l-bg.l,fg.a-bg.a,fg.b-bg.b,(fg.alpha-bg.alpha)*.7)
    val length=delta.sumOf { it*it };val amount=strength.coerceIn(0,100)/100.0
    fun values(p: PaletteLab) = doubleArrayOf(p.l-bg.l,p.a-bg.a,p.b-bg.b,(p.alpha-bg.alpha)*.7)
    fun distance(p: PaletteLab): Double { val v=values(p);return (0..3).sumOf { val d=v[it]-delta[it]*amount;d*d } }
    var nearest=0;var nearestDistance=Double.POSITIVE_INFINITY
    val candidates=mutableListOf<Pair<Int,Double>>()
    for(i in palette.indices) {
        val p=PaletteLab(if(i==transparentIndex) 0 else palette[i]);val d=distance(p)
        if(d<nearestDistance) {nearest=i;nearestDistance=d}
        if(length<1e-12) continue
        val v=values(p);val t=(0..3).sumOf { v[it]*delta[it] }/length
        val perpendicular=(0..3).sumOf { val e=v[it]-delta[it]*t;e*e }
        if(t>=-.02 && t<=1.02 && perpendicular<=.012) candidates.add(i to t.coerceIn(0.0,1.0))
    }
    if(candidates.isEmpty() || length<1e-12) return nearest
    candidates.sortWith(compareBy<Pair<Int,Double>> { it.second }.thenBy { it.first })
    var lower=candidates.first();var upper=candidates.last()
    for(c in candidates) {
        if(c.second<=amount) lower=c
        if(c.second>=amount) {upper=c;break}
    }
    if(amount<=candidates.first().second) return candidates.first().first
    if(amount>=candidates.last().second) return candidates.last().first
    if(abs(upper.second-lower.second)<1e-12) return nearest
    val fraction=(amount-lower.second)/(upper.second-lower.second)
    return if(fraction>bayerThreshold(x,y)) upper.first else lower.first
}

private fun bayerThreshold(x: Int,y: Int): Double {
    val bayer=intArrayOf(0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)
    return (bayer[(y and 3)*4+(x and 3)]+.5)/16
}

/** Retouch never flattens alpha when the palette has no same-alpha candidate. */
internal fun retouchPaletteIndex(palette: IntArray, source: Int, x: Int, y: Int, transparentIndex: Int? = null): Int {
    val alpha=source ushr 24
    if(alpha==0) return -1
    val target=PaletteLab(source)
    fun sq(x: Double)=x*x
    fun dist(p: PaletteLab)=sq(p.l-target.l)+sq(p.a-target.a)+sq(p.b-target.b)
    val candidates=mutableListOf<Pair<Int,PaletteLab>>()
    for(i in palette.indices) {
        if(i==transparentIndex || palette[i] ushr 24!=alpha) continue
        if(palette[i]==source) return i
        candidates.add(i to PaletteLab(palette[i]))
    }
    if(candidates.isEmpty()) return -1
    candidates.sortWith(compareBy<Pair<Int,PaletteLab>> { dist(it.second) }.thenBy { it.first })
    val near=candidates.take(8)
    var low=near.first().first;var high=low;var mix=0.0;var error=dist(near.first().second)
    for(i in near.indices) for(j in i+1 until near.size) {
        val a=near[i].second;val b=near[j].second
        val dl=b.l-a.l;val da=b.a-a.a;val db=b.b-a.b;val len=dl*dl+da*da+db*db
        if(len<1e-12) continue
        val t=(((target.l-a.l)*dl+(target.a-a.a)*da+(target.b-a.b)*db)/len).coerceIn(0.0,1.0)
        val e=sq(a.l+dl*t-target.l)+sq(a.a+da*t-target.a)+sq(a.b+db*t-target.b)+.02*len*t*(1-t)
        if(e<error-1e-12) {error=e;low=near[i].first;high=near[j].first;mix=t}
    }
    return if(mix>bayerThreshold(x,y)) high else low
}
