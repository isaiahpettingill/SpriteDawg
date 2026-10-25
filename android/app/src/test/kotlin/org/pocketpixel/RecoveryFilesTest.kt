package org.pocketpixel
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test
class RecoveryFilesTest {
 @Test fun findsBackupWhenBaseMissingAndDeduplicatesWithoutNewFiles(){
   val dir=Files.createTempDirectory("spritedawg-recovery-").toFile()
   try {
     listOf("recovery.aseprite.bak","recovery-2.aseprite","recovery-2.aseprite.bak","recovery-3.aseprite.new","unrelated.bak").forEach { dir.resolve(it).writeText("test") }
     assertEquals(listOf("recovery-2.aseprite","recovery.aseprite"),recoveryBaseFiles(dir).map { it.name })
   } finally {dir.deleteRecursively()}
 }
}
