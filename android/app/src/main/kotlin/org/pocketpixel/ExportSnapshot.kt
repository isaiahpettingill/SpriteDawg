package org.pocketpixel

/** Read-only, bounded, straight RGBA snapshot for the portable export encoders. */
fun exportSnapshot(d: Document, current: Int, args: Map<String, Any?>): Map<String, Any?> {
    val scope = args["scope"] as? String ?: "current"
    var from = current; var to = current; var direction = 0; var repeat = 0
    when (scope) {
        "all" -> { from = 0; to = d.frames.lastIndex }
        "tag" -> {
            val index = (args["tag"] as? Number)?.toInt() ?: -1
            require(index in d.tags.indices) { "Select an existing tag" }
            val tag = d.tags[index]
            from = tag.from; to = tag.to; direction = tag.direction; repeat = tag.repeat
        }
        else -> require(scope == "current") { "Invalid export selection" }
    }
    require(from >= 0 && to >= from && to < d.frames.size) { "Invalid export frame range" }
    val indices = (from..to).toMutableList()
    if (args["animation"] == true) {
        if (direction == 1 || direction == 3) indices.reverse()
        if ((direction == 2 || direction == 3) && indices.size > 2) {
            indices.addAll(indices.subList(1, indices.size - 1).reversed().toList())
        }
    }
    require(d.width.toLong() * d.height * indices.size <= 8 * 1024 * 1024) {
        "Export is too large. Export fewer frames (32 MiB pixel limit)."
    }
    return mapOf(
        "width" to d.width, "height" to d.height,
        "frames" to indices.map { index ->
            val pixels = d.composite(index)
            ByteArray(pixels.size * 4).also { bytes -> pixels.forEachIndexed { i, color ->
                bytes[i*4] = (color ushr 16).toByte(); bytes[i*4+1] = (color ushr 8).toByte()
                bytes[i*4+2] = color.toByte(); bytes[i*4+3] = (color ushr 24).toByte()
            } }
        },
        "durations" to indices.map { d.frames[it].duration }, "indices" to indices,
        "repeat" to repeat,
        "tags" to d.tags.filter { it.from >= from && it.to <= to }.map {
            mapOf("name" to it.name, "from" to it.from - from, "to" to it.to - from,
                "direction" to it.direction, "repeat" to it.repeat)
        },
    )
}
