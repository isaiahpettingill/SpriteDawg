package org.pocketpixel
import org.junit.Assert.*
import org.junit.Test

class DefaultUserDataTest {
    private val raw = "  credits=\"Artist ✨\"\nlicense=\"CC BY 4.0\"\ntitle=\"Title\"\nother: { }\n"
    @Test fun newSpritesKeepRawTextAndRoundTrip() {
        val s = EditorSessions()
        repeat(2) {
            val session = s.add(newSprite(16,24,raw), unsaved=true)
            assertEquals(raw, Aseprite.read(Aseprite.write(session.engine.document)).data?.text)
            assertTrue(session.title.startsWith("Untitled"))
        }
        assertNull(newSprite(8,8,"").data)
    }
    @Test fun defaultsNeverCreateAnImplicitDocumentOrModifyImports() {
        val s = EditorSessions()
        s.initializePlaceholder(raw)
        assertTrue(s.documents.isEmpty())
        s.add(Document.create().also { it.data=UserData(text="imported") })
        s.initializePlaceholder(raw)
        assertEquals("imported",s.active.engine.document.data?.text)
        s.add(Document.create());s.initializePlaceholder(raw)
        assertNull(s.active.engine.document.data)
        s.close(s.activeId);s.close(s.activeId);s.initializePlaceholder(raw)
        assertTrue(s.documents.isEmpty())
    }
    @Test fun validatesUtf8BoundaryBeforeChanges() {
        assertEquals(65535,defaultUserData(mapOf("defaultUserData" to "a".repeat(65535))).length)
        assertThrows(IllegalArgumentException::class.java) { newSprite(8,8,"é".repeat(32768)) }
        assertThrows(IllegalArgumentException::class.java) { defaultUserData(mapOf("defaultUserData" to 1)) }
        val s=EditorSessions(); s.add(Document.create()); val before=Aseprite.write(s.active.engine.document)
        assertThrows(IllegalArgumentException::class.java) { s.initializePlaceholder("é".repeat(32768)) }
        assertArrayEquals(before,Aseprite.write(s.active.engine.document))
    }
    @Test fun explicitApplyKeepsMetadataAndUndo() {
        val e=EditorEngine();e.document.data=UserData(text="original",color=0xff123456.toInt(),properties=byteArrayOf(0,0,0,0))
        val before=Aseprite.write(e.document)
        e.edit(mapOf("action" to "userData","target" to "sprite","text" to raw))
        assertEquals(raw,e.document.data?.text);assertEquals(0xff123456.toInt(),e.document.data?.color)
        assertArrayEquals(byteArrayOf(0,0,0,0),e.document.data?.properties)
        e.undo();assertArrayEquals(before,Aseprite.write(e.document))
    }
}

