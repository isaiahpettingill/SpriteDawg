package org.pocketpixel
import org.junit.Assert.*
import org.junit.Test

class SessionTransferTest {
    private fun source():Document=Document.create(2,1).also {d->
        d.frames.clear();d.frames.add(Frame(75,mutableListOf(Cel(0,0,2,1,intArrayOf(0xffff0000.toInt(),0xff0000ff.toInt())))))
        d.frames.add(Frame(125,mutableListOf(Cel(0,0,0,0,intArrayOf(),link=0,data=UserData(text="linked")))))
        d.tags.add(Tag(1,1,2,3,byteArrayOf(1,2,3),"Tile variants",UserData(text="game:tile",color=0xff123456.toInt(),properties=byteArrayOf(8,0,0,0,0,0,0,0))))
    }
    @Test fun snapshotResolvesLinksAndPreservesMetadata(){
        val d=source();val before=Aseprite.write(d);val copy=TagTransfer.copy(d,0)
        assertEquals(125,copy.frames.single().duration);assertNull(copy.frames.single().cels.single()!!.link)
        assertArrayEquals(intArrayOf(0xffff0000.toInt(),0xff0000ff.toInt()),copy.frames.single().cels.single()!!.pixels)
        assertEquals("linked",copy.frames.single().cels.single()!!.data!!.text)
        assertEquals(0,copy.tags.single().from);assertEquals(0,copy.tags.single().to);assertEquals(3,copy.tags.single().repeat)
        assertEquals("game:tile",copy.tags.single().data!!.text);assertArrayEquals(byteArrayOf(8,0,0,0,0,0,0,0),copy.tags.single().data!!.properties);assertArrayEquals(before,Aseprite.write(d))
    }
    @Test fun pasteUndoAndSourceAreIndependent(){
        val s=EditorSessions();val src=s.add(source(),unsaved=true);s.copyTag(0);val dst=s.add(Document.create(2,1));s.pasteTag()
        val saved=Aseprite.write(dst.engine.document);assertEquals(2,dst.engine.document.frames.size)
        dst.engine.undo();assertEquals(1,dst.engine.document.frames.size);assertTrue(dst.engine.document.tags.isEmpty())
        dst.engine.redo();assertArrayEquals(saved,Aseprite.write(dst.engine.document));assertEquals(1,src.engine.document.tags.single().from)
        s.select(src.id);assertSame(src,s.active)
    }
    @Test fun mismatchDoesNotCommit(){
        val s=EditorSessions();s.add(source());s.copyTag(0);val dst=s.add(Document.create(3,1));val before=Aseprite.write(dst.engine.document)
        try{s.pasteTag();fail("must reject canvas mismatch")}catch(_:IllegalArgumentException){}
        assertArrayEquals(before,Aseprite.write(dst.engine.document));assertEquals(false,dst.engine.state(false)["canUndo"])
    }
    @Test fun dirtyCloseRequiresExplicitDiscard(){
        val s=EditorSessions();val a=s.add(source(),unsaved=true);val b=s.add(Document.create())
        try{s.close(a.id);fail("must confirm discard")}catch(_:IllegalArgumentException){}
        s.close(b.id);assertEquals(a.id,s.activeId);s.close(a.id,true);assertEquals(1,s.documents.size)
    }
    @Test fun pasteAsNewAndDestinationLinksRemainIndependent(){
        val s=EditorSessions();val origin=s.add(source());s.copyTag(0);s.pasteTagAsNew()
        assertEquals("Tile variants",s.active.title);assertEquals(2,origin.engine.document.frames.size)
        val target=source();TagTransfer.paste(target,-1,TagTransfer.copy(source(),0))
        assertEquals(1,target.frames[2].cels[0]!!.link);assertArrayEquals(intArrayOf(0xffff0000.toInt(),0xff0000ff.toInt()),target.resolved(2,0)!!.pixels)
    }
    @Test fun indexedPerFramePalettesSurvive(){
        val d=source();d.depth=8;d.transparentIndex=0
        d.frames[0].palette=intArrayOf(0,0xffff0000.toInt(),0xff0000ff.toInt());d.frames[0].cels[0]!!.pixels=intArrayOf(1,2)
        d.frames[1].palette=intArrayOf(0,0xff00ff00.toInt(),0xffffff00.toInt())
        val target=Document.create(2,1);target.depth=8;target.frames[0].palette=intArrayOf(0,0xff000000.toInt())
        TagTransfer.paste(target,0,TagTransfer.copy(d,0));val round=Aseprite.read(Aseprite.write(target))
        assertArrayEquals(intArrayOf(1,2),round.frames[1].cels[0]!!.pixels);assertArrayEquals(d.frames[1].palette,round.frames[1].palette)
    }
    @Test fun aggregateBudgetFailurePreservesDocumentAndUndo(){
        val s=EditorSessions(4096);val a=s.add(Document.create(2,1));val before=Aseprite.write(a.engine.document)
        try {a.engine.applyDocumentEdit {it.data=UserData(text="x".repeat(5000))};fail("must reject budget overflow")}catch(_:IllegalArgumentException){}
        assertArrayEquals(before,Aseprite.write(a.engine.document));assertEquals(false,a.engine.state(false)["canUndo"])
        try{s.add(Document.create(2,1).also {it.data=UserData(text="x".repeat(5000))});fail("must reject oversized document")}catch(_:IllegalArgumentException){}
        assertEquals(1,s.documents.size);assertEquals(a.id,s.activeId)
    }
    @Test fun recoveryStagesGrowingAndShrinkingDocumentsAtomically(){
        val s=EditorSessions(9000)
        val a=s.add(Document.create(2,1).also {it.data=UserData(text="a".repeat(1000))})
        val b=s.add(Document.create(2,1).also {it.data=UserData(text="b".repeat(2000))})
        val restored=s.restoreDecoded(listOf(a.id to Document.create(2,1).also {it.data=UserData(text="a".repeat(2000))},b.id to Document.create(2,1).also {it.data=UserData(text="b".repeat(1000))}))
        assertEquals(2000,restored[0].engine.document.data!!.text!!.length);assertEquals(1000,restored[1].engine.document.data!!.text!!.length);assertEquals(b.id,s.activeId)
    }
}
