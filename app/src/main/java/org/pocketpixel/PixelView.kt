package org.pocketpixel

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import kotlin.math.*

/** Native Android canvas; Compose owns controls, this view owns pointer sampling. */
class PixelView(context: Context) : View(context) {
    lateinit var editor: Editor
    var onChanged: () -> Unit = {}
    var onError: (String) -> Unit = {}
    var tool = Tool.Pencil
    var color = 0xff000000.toInt()
    var brush = 1
    var grid = false
    var onion = false
    private val paint =
        Paint().apply {
            isAntiAlias = false
            isFilterBitmap = false
        }
    private var zoom = 1f
    private var ox = 0f
    private var oy = 0f
    private var fitted = false
    private var lastDoc: Document? = null
    private var active: Cel? = null
    private var before: Document? = null
    private var shapeBase: Cel? = null
    private var sx = 0
    private var sy = 0
    private var lx = 0
    private var ly = 0
    private var multi = false
    private var cx = 0f
    private var cy = 0f
    private var distance = 0f
    private val bitmaps = mutableMapOf<Int, Bitmap>()
    private val indexedBuffers = mutableMapOf<Int, IntArray>()
    private var revision = -1

    fun refresh() {
        if (!::editor.isInitialized) return
        if (lastDoc?.width != editor.doc.width || lastDoc?.height != editor.doc.height)
            fitted = false
        lastDoc = editor.doc
        revision = -1
        invalidate()
    }

    fun fit() {
        fitted = false
        invalidate()
    }

    private fun setFit() {
        val d = editor.doc
        zoom = min(width.toFloat() / d.width, height.toFloat() / d.height) * 0.85f
        ox = (width - d.width * zoom) / 2
        oy = (height - d.height * zoom) / 2
        fitted = true
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        fitted = false
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!::editor.isInitialized) return
        val d = editor.doc
        if (!fitted) setFit()
        canvas.drawColor(0xff17191e.toInt())
        canvas.save()
        canvas.translate(ox, oy)
        canvas.scale(zoom, zoom)
        canvas.clipRect(0, 0, d.width, d.height)
        for (y in 0 until d.height step 8) for (x in 0 until d.width step 8) {
            paint.color = if ((x / 8 + y / 8) % 2 == 0) 0xff42454c.toInt() else 0xff30333a.toInt()
            paint.alpha = 255
            canvas.drawRect(
                x.toFloat(),
                y.toFloat(),
                min(x + 8, d.width).toFloat(),
                min(y + 8, d.height).toFloat(),
                paint,
            )
        }
        fun bitmap(key: Int, pixels: IntArray, w: Int, h: Int, update: Boolean): Bitmap {
            var b = bitmaps[key]
            if (b == null || b.width != w || b.height != h) {
                b?.recycle()
                b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bitmaps[key] = b
                b.setPixels(pixels, 0, w, 0, 0, w, h)
            } else if (update) b.setPixels(pixels, 0, w, 0, 0, w, h)
            return b
        }
        val changed = revision != editor.revision
        if (onion && editor.frame > 0 && !editor.playing) {
            val b =
                if (changed || bitmaps[-1] == null)
                    bitmap(-1, d.composite(editor.frame - 1), d.width, d.height, true)
                else bitmaps[-1]!!
            paint.alpha = 65
            canvas.drawBitmap(b, 0f, 0f, paint)
        }
        for (l in d.layers.indices) {
            if (!d.layers[l].visible) continue
            val c = if (l == editor.layer && active != null) active else d.resolved(editor.frame, l)
            if (c == null) continue
            val update = changed || (l == editor.layer && active != null)
            val pixels =
                if (d.depth == 8 && update)
                    indexedBuffers
                        .getOrPut(l) { IntArray(c.pixels.size) }
                        .let { buffer ->
                            val out =
                                if (buffer.size == c.pixels.size) buffer
                                else IntArray(c.pixels.size).also { indexedBuffers[l] = it }
                            for (i in out.indices) out[i] = d.display(c.pixels[i], editor.frame, l)
                            out
                        }
                else c.pixels
            val b = bitmap(l, pixels, c.width, c.height, update)
            paint.alpha = (c.opacity * d.layers[l].opacity + 127) / 255
            canvas.drawBitmap(b, c.x.toFloat(), c.y.toFloat(), paint)
        }
        if (grid && zoom >= 8) {
            paint.color = 0xff000000.toInt()
            paint.alpha = 90
            paint.strokeWidth = 1f / zoom
            for (x in 0..d.width) canvas.drawLine(
                x.toFloat(),
                0f,
                x.toFloat(),
                d.height.toFloat(),
                paint,
            )
            for (y in 0..d.height) canvas.drawLine(
                0f,
                y.toFloat(),
                d.width.toFloat(),
                y.toFloat(),
                paint,
            )
        }
        canvas.restore()
        revision = editor.revision
    }

    private fun pixel(x: Float, y: Float) =
        Pair(
            floor((x - ox) / zoom).toInt().coerceIn(0, editor.doc.width - 1),
            floor((y - oy) / zoom).toInt().coerceIn(0, editor.doc.height - 1),
        )

    private fun cancelStroke() {
        before?.let { editor.doc = it }
        active = null
        before = null
        revision = -1
        invalidate()
    }

    private fun drawTo(x: Int, y: Int) {
        val c = active ?: return
        val d = editor.doc
        val ink = d.drawingColor(color, editor.frame, tool == Tool.Eraser)
        when (tool) {
            Tool.Pencil,
            Tool.Eraser -> Drawing.line(c, lx, ly, x, y, ink, brush, d.width, d.height)
            Tool.Line,
            Tool.Rect -> {
                val original = active!!
                shapeBase!!.pixels.copyInto(original.pixels)
                if (tool == Tool.Line)
                    Drawing.line(original, sx, sy, x, y, ink, brush, d.width, d.height)
                else {
                    Drawing.line(original, sx, sy, x, sy, ink, brush, d.width, d.height)
                    Drawing.line(original, x, sy, x, y, ink, brush, d.width, d.height)
                    Drawing.line(original, x, y, sx, y, ink, brush, d.width, d.height)
                    Drawing.line(original, sx, y, sx, sy, ink, brush, d.width, d.height)
                }
            }
            else -> Unit
        }
        lx = x
        ly = y
        invalidate()
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!::editor.isInitialized || editor.playing || editor.busy) return true
        parent.requestDisallowInterceptTouchEvent(true)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                multi = false
                cx = e.x
                cy = e.y
                if (tool != Tool.Pan) {
                    val p = pixel(e.x, e.y)
                    sx = p.first
                    sy = p.second
                    lx = sx
                    ly = sy
                    if (tool == Tool.Pick) {
                        editor.color =
                            editor.doc.composite(editor.frame)[sy * editor.doc.width + sx]
                        onChanged()
                        return true
                    }
                    if (!editor.doc.layers[editor.layer].visible) {
                        onError(
                            "The active layer is hidden. Show it or choose a visible layer in Layers / Frames."
                        )
                        return true
                    }
                    if (
                        tool == Tool.Eraser &&
                            editor.doc.depth == 8 &&
                            editor.doc.layers[editor.layer].flags and 8 != 0
                    ) {
                        onError(
                            "Indexed background layers are opaque in Aseprite. Choose a normal image layer to erase to transparency."
                        )
                        return true
                    }
                    before = editor.doc.copyDeep()
                    // Shape previews use a separate buffer; the document stays at its pre-stroke
                    // state.
                    try {
                        active = editor.doc.editable(editor.frame, editor.layer).copyDeep()
                    } catch (error: IllegalArgumentException) {
                        cancelStroke()
                        onError(error.message ?: "Cel cannot be edited safely")
                        return true
                    }
                    shapeBase = active!!.copyDeep()
                    if (tool == Tool.Fill)
                        Drawing.fill(
                            active!!,
                            sx,
                            sy,
                            editor.doc.drawingColor(color, editor.frame),
                            editor.doc.width,
                            editor.doc.height,
                        )
                    else drawTo(sx, sy)
                    invalidate()
                }
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                cancelStroke()
                multi = true
                cx = (e.getX(0) + e.getX(1)) / 2
                cy = (e.getY(0) + e.getY(1)) / 2
                distance = hypot(e.getX(1) - e.getX(0), e.getY(1) - e.getY(0))
            }
            MotionEvent.ACTION_MOVE -> {
                if (multi && e.pointerCount >= 2) {
                    val nx = (e.getX(0) + e.getX(1)) / 2
                    val ny = (e.getY(0) + e.getY(1)) / 2
                    val nd = hypot(e.getX(1) - e.getX(0), e.getY(1) - e.getY(0))
                    val z = (zoom * if (distance > 0) nd / distance else 1f).coerceIn(0.25f, 160f)
                    ox = nx - (cx - ox) * z / zoom
                    oy = ny - (cy - oy) * z / zoom
                    zoom = z
                    cx = nx
                    cy = ny
                    distance = nd
                    invalidate()
                } else if (!multi && tool == Tool.Pan) {
                    ox += e.x - cx
                    oy += e.y - cy
                    cx = e.x
                    cy = e.y
                    invalidate()
                } else if (!multi && active != null && tool != Tool.Fill) {
                    for (i in 0 until e.historySize) {
                        val p = pixel(e.getHistoricalX(i), e.getHistoricalY(i))
                        drawTo(p.first, p.second)
                    }
                    val p = pixel(e.x, e.y)
                    drawTo(p.first, p.second)
                }
            }
            MotionEvent.ACTION_UP -> {
                val original = before
                val c = active
                if (original != null && c != null) {
                    editor.history.push(original)
                    editor.doc.frames[editor.frame].cels[editor.layer] = c
                    editor.changed()
                    onChanged()
                }
                before = null
                active = null
                performClick()
                invalidate()
            }
            MotionEvent.ACTION_CANCEL -> cancelStroke()
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }
}
