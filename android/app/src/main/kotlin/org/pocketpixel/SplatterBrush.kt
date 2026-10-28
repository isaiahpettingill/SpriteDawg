package org.pocketpixel

import kotlin.math.*

/** Spaced seeded droplet bursts. Strongest coverage wins; blend once per gesture. */
internal fun splatterPixels(points: List<Pair<Int,Int>>, width: Int, height: Int, size: Int,
    seed: Long = 1L, mirrorX: Boolean = false, mirrorY: Boolean = false,
    mirrorDiagonal: Boolean = false, mirrorAntiDiagonal: Boolean = false): Map<Int,Int> {
    val out = linkedMapOf<Int,Int>()
    val symmetry=StrokeSymmetry(width,height,mirrorX,mirrorY,mirrorDiagonal,mirrorAntiDiagonal)
    val bounds=symmetry.sourceBounds
    if (points.isEmpty()) return out
    val path = mutableListOf<Pair<Int,Int>>()
    for (point in points) {
        if (path.lastOrNull() == point) continue
        while (path.size >= 2) {
            val a = path[path.size-2]; val b = path.last()
            val dx = b.first-a.first; val dy = b.second-a.second
            val ex = point.first-b.first; val ey = point.second-b.second
            if (dx*ey != dy*ex || dx*ex+dy*ey <= 0) break
            path.removeAt(path.lastIndex)
        }
        path.add(point)
    }
    fun emit(x: Int, y: Int, coverage: Int) {
        for ((xx,yy) in symmetry.points(x,y)) {
            val key = yy*width+xx
            out[key] = max(out[key] ?: 0, coverage)
        }
    }
    val stamped = mutableSetOf<Pair<Int,Int>>()
    fun stamp(x: Int, y: Int) {
        if (!stamped.add(Pair(x,y))) return
        val left = x-size/2; val top = y-size/2
        if (left > bounds.right || top > bounds.bottom || left+size <= bounds.left || top+size <= bounds.top) return
        var state = (x*374761393L+y*668265263L+(seed and 0xffffffffL)*69069L) and 0xffffffffL
        fun random(): Int {
            state = (state*1664525L+1013904223L) and 0xffffffffL
            return (state ushr 16).toInt()
        }
        val count = if (size == 1) 1 else 2+size/3
        val maxDiameter = max(1,size/5)
        for (drop in 0 until count) {
            val cx = if (drop == 0) size/2 else random()%size
            val cy = if (drop == 0) size/2 else random()%size
            val diameter = 1+random()%maxDiameter
            val coverage = 64+random()%192
            for (oy in 0 until diameter) for (ox in 0 until diameter) {
                val dx = 2*ox-diameter+1; val dy = 2*oy-diameter+1
                if (dx*dx+dy*dy > diameter*diameter) continue
                val px = cx-diameter/2+ox; val py = cy-diameter/2+oy
                val bx = 2*px-size+1; val by = 2*py-size+1
                if (px !in 0 until size || py !in 0 until size || bx*bx+by*by > size*size) continue
                emit(left+px,top+py,coverage)
            }
        }
    }
    stamp(path.first().first,path.first().second)
    val spacing = max(1,size/2)
    var travelled = 0
    for (i in 1 until path.size) {
        val from = path[i-1]; val to = path[i]
        var x = from.first; var y = from.second
        val dx = abs(to.first-x); val dy = -abs(to.second-y)
        val sx = if (x < to.first) 1 else -1; val sy = if (y < to.second) 1 else -1
        var error = dx+dy
        while (x != to.first || y != to.second) {
            val twice = error*2
            if (twice >= dy) { error+=dy; x+=sx }
            if (twice <= dx) { error+=dx; y+=sy }
            travelled++
            if (travelled%spacing == 0) stamp(x,y)
        }
    }
    return out
}
