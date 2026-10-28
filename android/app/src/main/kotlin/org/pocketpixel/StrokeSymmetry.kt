package org.pocketpixel

/** Integer orthogonal transforms about the canvas center, never aspect-ratio scaling. */
internal data class SymmetryTransform(val xx: Int, val xy: Int, val yx: Int, val yy: Int) {
    fun compose(other: SymmetryTransform) = SymmetryTransform(
        xx*other.xx+xy*other.yx, xx*other.xy+xy*other.yy,
        yx*other.xx+yy*other.yx, yx*other.xy+yy*other.yy
    )
    fun vector(x: Int, y: Int) = Pair(xx*x+xy*y, yx*x+yy*y)
    fun point(x: Int, y: Int, width: Int, height: Int): Pair<Int,Int> {
        val dx=2*x-width+1; val dy=2*y-height+1
        // Mixed-parity rectangles land halfway between pixels. Round ties toward
        // top/left, once after the exact transform (not per generator).
        return Pair(Math.floorDiv(xx*dx+xy*dy+width-1,2), Math.floorDiv(yx*dx+yy*dy+height-1,2))
    }
}

/** Inclusive source-pixel bounds whose exact reflected pixels can reach the canvas. */
internal data class SymmetryBounds(val left: Int,val top: Int,val right: Int,val bottom: Int)

/** Closure of all enabled reflections. Every exact transform appears only once. */
internal class StrokeSymmetry(
    private val width: Int, private val height: Int,
    mirrorX: Boolean=false, mirrorY: Boolean=false,
    mirrorDiagonal: Boolean=false, mirrorAntiDiagonal: Boolean=false,
    private val wrap: Boolean=false
) {
    val transforms: List<SymmetryTransform>
    val sourceBounds: SymmetryBounds
    init {
        val identity=SymmetryTransform(1,0,0,1)
        val x=SymmetryTransform(-1,0,0,1); val y=SymmetryTransform(1,0,0,-1)
        val diagonal=SymmetryTransform(0,1,1,0); val antiDiagonal=SymmetryTransform(0,-1,-1,0)
        val generators=mutableListOf<SymmetryTransform>()
        if(mirrorX) generators.add(x)
        if(mirrorY) generators.add(y)
        if(mirrorDiagonal) generators.add(diagonal)
        if(mirrorAntiDiagonal) generators.add(antiDiagonal)
        val closure=linkedSetOf(identity)
        val queue=mutableListOf(identity)
        var cursor=0
        while(cursor < queue.size) {
            val t=queue[cursor++]
            for(g in generators) {
                val next=g.compose(t)
                if(closure.add(next)) queue.add(next)
            }
        }
        // Stable legacy X/Y order also preserves seeded effect traversal.
        transforms=queue
        // Inverse bounds use the exact integer offset for each matrix. A single
        // union rectangle is conservative (the actual union can be cross-shaped)
        // but remains bounded by max(width,height)+1 on each axis (half-pixel ties).
        var left=0;var top=0;var right=width-1;var bottom=height-1
        fun interval(sign: Int,offset: Int,limit: Int): Pair<Int,Int> =
            if(sign>0) -offset to limit-1-offset else offset-limit+1 to offset
        for(t in transforms) {
            val (ox,oy)=t.point(0,0,width,height)
            val bx=if(t.xx!=0) interval(t.xx,ox,width) else interval(t.yx,oy,height)
            val by=if(t.xy!=0) interval(t.xy,ox,width) else interval(t.yy,oy,height)
            left=minOf(left,bx.first);right=maxOf(right,bx.second)
            top=minOf(top,by.first);bottom=maxOf(bottom,by.second)
        }
        sourceBounds=SymmetryBounds(left,top,right,bottom)
    }
    fun points(x: Int,y: Int): Set<Pair<Int,Int>> {
        val out=linkedSetOf<Pair<Int,Int>>()
        for(t in transforms) {
            val p=transformedPoint(t,x,y)
            if(p.first in 0 until width && p.second in 0 until height) out.add(p)
        }
        return out
    }
    fun transformedPoint(t: SymmetryTransform,x: Int,y: Int): Pair<Int,Int> {
        val sx=if(wrap) Math.floorMod(x,width) else x
        val sy=if(wrap) Math.floorMod(y,height) else y
        val p=t.point(sx,sy,width,height)
        return if(wrap) Math.floorMod(p.first,width) to Math.floorMod(p.second,height) else p
    }
    fun canonical(x: Int,y: Int): Pair<Int,Int> = transforms.map { transformedPoint(it,x,y) }.minWithOrNull(
        compareBy<Pair<Int,Int>> { it.first }.thenBy { it.second }
    ) ?: Pair(x,y)
}

/** Closest periodic representative to an interval center, or null if absent. */
internal fun periodicRepresentative(start: Int,end: Int,coordinate: Int,period: Int): Int? {
    val first=start+Math.floorMod(coordinate-start,period)
    if(first>end) return null
    val steps=(end-first)/period
    val nearest=((start+end-2*first+period)/(2*period)).coerceIn(0,steps)
    return first+nearest*period
}
