package org.pocketpixel

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

/** Independent expectations from Aseprite blend_funcs.cpp and LibreSprite color_scales.h. */
class ReferenceCompatibilityTest {
    @Test fun legacySixBitPaletteMatchesEveryOfficialValue() {
        val original=Aseprite.write(Document.create(1,1))
        val input=ByteBuffer.wrap(original).order(ByteOrder.LITTLE_ENDIAN)
        val chunks=mutableListOf<ByteArray>(); var offset=144
        while(offset<original.size) {
            val size=input.getInt(offset); val type=input.getShort(offset+4).toInt() and 65535
            if(type!=0x2019) chunks.add(original.copyOfRange(offset,offset+size))
            offset+=size
        }
        val legacy=Writer().apply { w(1); b(0); b(64); for(v in 0..63) { b(v); b(v); b(v) } }.result()
        chunks.add(Writer().apply { d(legacy.size+6); w(0x11); bytes(legacy) }.result())
        val frame=Writer().apply { d(16+chunks.sumOf { it.size }); w(0xf1fa); w(chunks.size); w(100); zeros(2); d(0); chunks.forEach { bytes(it) } }.result()
        val header=original.copyOf(128); ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN).putInt(128+frame.size)
        val d=Aseprite.read(header+frame)
        for(v in 0..63) { val expected=(v shl 2) or (v ushr 4); assertEquals("six-bit $v",0xff000000.toInt() or (expected*0x010101),d.frames[0].palette[v]) }
    }
    @Test fun normalBlendMatchesIndependentReference() {
        assertEquals(0xff76a287.toInt(),over(0xff00cdf9.toInt(),0xffed7614.toInt(),128))
        assertEquals(0x00123456,over(0,0x00123456))
    }
    @Test fun removingPaletteKeyFrameKeepsInheritedColorsAndNames() {
        val d=Document.create(1,1); d.depth=8
        d.frames[0].palette=intArrayOf(0,0xff000000.toInt(),0xff000000.toInt())
        d.addFrame(0,true); d.frames[1].palette[1]=0xffff0000.toInt(); d.frames[1].paletteNames[1]="Inherited red"
        d.addFrame(1,true); d.frames[2].palette[2]=0xff00ff00.toInt()
        d.frames[2].metadata.add(0x2019 to Writer().apply { d(3); d(2); d(2); zeros(8); w(0); b(0); b(255); b(0); b(255) }.result())
        d.frames[2].cels[0]=Cel(0,0,1,1,intArrayOf(1)); d.removeFrame(1)
        val round=Aseprite.read(Aseprite.write(d))
        assertEquals(0xffff0000.toInt(),round.composite(1)[0])
        assertEquals("Inherited red",round.frames[1].paletteNames[1])
    }
}
