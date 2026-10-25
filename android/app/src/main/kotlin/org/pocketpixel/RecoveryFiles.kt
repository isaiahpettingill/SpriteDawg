package org.pocketpixel
import java.io.File

/** Discover only committed recovery bases, including legacy AtomicFile backups.
 * A .new file has not committed and must never displace the last valid copy. */
internal fun recoveryBaseFiles(directory: File): List<File> = directory.listFiles()
    ?.filter { it.isFile && Regex("recovery(?:-[0-9]+)?\\.aseprite(?:\\.bak)?").matches(it.name) }
    ?.map { File(directory,it.name.removeSuffix(".bak")) }
    ?.distinctBy { it.name }
    ?.sortedBy { it.name } ?: emptyList()
