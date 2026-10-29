package org.pocketpixel

import java.nio.ByteBuffer
import java.nio.ByteOrder

private fun Map<String, Any?>.regionInt(key: String): Int {
    val value = this[key]
    require(value is Int || value is Long) { "Invalid region $key" }
    val number = (value as Number).toLong()
    require(number in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) { "Invalid region $key" }
    return number.toInt()
}
private fun regionBounds(d: Document, a: Map<String, Any?>): List<Int> {
    val x=a.regionInt("x"); val y=a.regionInt("y")
    val w=a.regionInt("width"); val h=a.regionInt("height")
    require(x>=0 && y>=0 && w>0 && h>0 && x.toLong()+w<=d.width && y.toLong()+h<=d.height) { "Selection is outside the canvas" }
    return listOf(x,y,w,h)
}
fun copyRegion(d: Document, frame: Int, layer: Int, a: Map<String, Any?>): Map<String, Any?> {
    val (x,y,w,h)=regionBounds(d,a)
    require(d.layers[layer].visible) { "Show this layer before copying" }
    require(w.toLong()*h<=1048576) { "Selection clipboard is limited to 1,048,576 pixels" }
    val c=d.resolved(frame,layer)
    val empty=if(d.depth==8) d.transparentIndex else 0
    val pixels=ByteBuffer.allocate(w*h*4).order(ByteOrder.LITTLE_ENDIAN)
    for(index in 0 until w*h) {
        val i=x+index%w; val j=y+index/w
        pixels.putInt(if(c!=null && i>=c.x && j>=c.y && i<c.x+c.width && j<c.y+c.height)
            c.pixels[(j-c.y)*c.width+i-c.x] else empty)
    }
    return mapOf("width" to w,"height" to h,"depth" to d.depth,"transparentIndex" to d.transparentIndex,
        "palette" to d.frames[frame].palette.map { it.toLong() and 0xffffffffL },"pixels" to pixels.array())
}
fun editRegion(d: Document, frame: Int, layer: Int, a: Map<String, Any?>) {
    require(d.layers[layer].visible) { "Show this layer before editing" }
    require(d.layers[layer].flags and 2 != 0) { "This layer is locked" }
    require(d.layers[layer].flags and 8 == 0) { "Convert this background layer to transparent before editing a region" }
    val (x,y,w,h)=regionBounds(d,a)
    val operation=a["operation"]
    require(operation in listOf("delete","move","paste")) { "Unknown region operation" }
    var copied: Map<*,*>?=null
    var tx=x; var ty=y
    if(operation=="move") {
        val dx=a.regionInt("dx"); val dy=a.regionInt("dy")
        require(x.toLong()+dx in 0L..d.width.toLong() && y.toLong()+dy in 0L..d.height.toLong()) { "Selection is outside the canvas" }
        tx+=dx; ty+=dy
        regionBounds(d,mapOf("x" to tx,"y" to ty,"width" to w,"height" to h))
        copied=copyRegion(d,frame,layer,a)
    } else if(operation=="paste") {
        copied=a["clipboard"] as? Map<*,*> ?: error("Copy a region first")
        require(copied["depth"] == d.depth && copied["width"] == w &&
            copied["height"] == h) { "Incompatible selection clipboard" }
        if(d.depth==8) {
            val palette=copied["palette"] as? List<*>
            require(copied["transparentIndex"] == d.transparentIndex && palette!=null &&
                palette.size==d.frames[frame].palette.size && palette.indices.all { (palette[it] as? Number)?.toInt()==d.frames[frame].palette[it] }) { "Selection palette differs from this frame" }
        }
    }
    val pixels=copied?.get("pixels") as? ByteArray
    if(copied!=null) require(pixels!=null && pixels.size==w*h*4 && w.toLong()*h<=1048576) { "Invalid clipboard pixels" }
    val values=pixels?.let { ByteBuffer.wrap(it).order(ByteOrder.LITTLE_ENDIAN) }
    if(values!=null && d.depth==8) for(i in 0 until w*h) require(values.getInt(i*4) in d.frames[frame].palette.indices) { "Invalid clipboard index" }
    val c=d.editable(frame,layer)
    val empty=if(d.depth==8) d.transparentIndex else 0
    if(operation!="paste") for(j in y until y+h) for(i in x until x+w) c.pixels[(j-c.y)*c.width+i-c.x]=empty
    if(values!=null) for(j in 0 until h) for(i in 0 until w) c.pixels[(ty+j-c.y)*c.width+tx+i-c.x]=values.getInt((j*w+i)*4)
}
