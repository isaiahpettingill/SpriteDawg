package org.pocketpixel

fun defaultUserData(args: Map<String, Any?>): String {
    val value = args["defaultUserData"] ?: ""
    require(value is String) { "Default user data must be text" }
    require(value.toByteArray(Charsets.UTF_8).size <= 65535) { "User data exceeds 65,535 UTF-8 bytes" }
    return value
}
fun newSprite(width: Int, height: Int, text: String): Document {
    defaultUserData(mapOf("defaultUserData" to text))
    return Document.create(width, height).also {
        if (text.isNotEmpty()) it.data = UserData(text = text)
    }
}
