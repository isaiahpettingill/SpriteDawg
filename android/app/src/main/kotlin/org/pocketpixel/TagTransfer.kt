package org.pocketpixel

object TagTransfer {
    fun copy(source: Document, index: Int): Document {
        require(index in source.tags.indices) { "Choose a tag to copy" }
        val copy = Aseprite.read(Aseprite.write(source))
        val tag = copy.tags[index].copy()
        var decodedPixels=0L
        for(f in tag.from..tag.to)for(l in copy.layers.indices){
            decodedPixels+=copy.resolved(f,l)?.pixels?.size ?: 0
            require(decodedPixels<=16L*1024*1024) { "Copied tag exceeds the 16 Mi decoded-pixel budget once links are made independent." }
        }
        for(f in tag.from..tag.to)for(l in copy.layers.indices)copy.frames[f].cels[l]=copy.resolved(f,l)?.copyDeep()
        val profiles = copy.frames.flatMap { it.metadata }.filter { it.first == 0x2007 }
        val frames = copy.frames.subList(tag.from, tag.to + 1).toList()
        copy.frames.clear(); copy.frames.addAll(frames)
        copy.frames.forEach { it.metadata.removeAll { m -> m.first == 0x2007 } }
        copy.frames.first().metadata.addAll(0, profiles)
        tag.to -= tag.from; tag.from = 0
        copy.tags.clear(); copy.tags.add(tag)
        return copy
    }
    private fun bytes(a: ByteArray?, b: ByteArray?) = if(a == null || b == null) a == null && b == null else a.contentEquals(b)
    private fun data(a: UserData?, b: UserData?) = a?.text == b?.text && a?.color == b?.color && bytes(a?.properties,b?.properties)
    fun paste(target: Document, after: Int, section: Document) {
        require(after in -1 until target.frames.size) { "Invalid paste position" }
        require(target.width == section.width && target.height == section.height) { "Tag paste needs matching canvas dimensions. Resize explicitly first." }
        require(target.depth == section.depth) { "Tag paste needs matching color modes. Convert explicitly first." }
        require(target.depth != 8 || target.transparentIndex == section.transparentIndex) { "Tag paste needs matching transparent palette indices. No indices were changed." }
        require(target.layers.size == section.layers.size) { "Tag paste needs matching layers (same names and order). No layers were discarded." }
        target.layers.zip(section.layers).forEachIndexed { i,(a,b) ->
            require(a.name == b.name && a.flags == b.flags && a.visible == b.visible && a.opacity == b.opacity && bytes(a.uuid,b.uuid) && data(a.data,b.data)) { "Layer ${i+1} differs in name, order, properties or metadata. Align layers explicitly before pasting." }
        }
        val a=target.frames.flatMap { it.metadata }.filter { it.first == 0x2007 }.map { it.second }
        val b=section.frames.flatMap { it.metadata }.filter { it.first == 0x2007 }.map { it.second }
        require(a.size == b.size && a.zip(b).all { bytes(it.first,it.second) }) { "Color profile metadata differs; tag paste refused." }
        require(target.tags.size+section.tags.size<=65535) { "Too many tags" }
        val count=section.frames.size
        require(target.frames.size+count<=4096) { "Tag paste exceeds 4096 frames" }
        val clone=Aseprite.read(Aseprite.write(section)); clone.detachLinks()
        target.frames.forEach { f -> f.cels.forEach { c -> if(c?.link!=null && c.link!!>after)c.link=c.link!!+count } }
        clone.frames.forEach { it.metadata.removeAll { m -> m.first == 0x2007 } }
        target.tags.forEach { if(it.from>after)it.from+=count; if(it.to>after)it.to+=count }
        target.frames.addAll(after+1,clone.frames)
        clone.tags.forEach { it.from+=after+1;it.to+=after+1;target.tags.add(it) }
        Aseprite.read(Aseprite.write(target))
    }
}
