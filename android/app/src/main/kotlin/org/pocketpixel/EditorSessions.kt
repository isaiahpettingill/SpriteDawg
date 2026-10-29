package org.pocketpixel

class EditorSession(val id: Int, var title: String = "Untitled $id") {
    val engine = EditorEngine()
    var path: String? = null
    // Only old URI-tail titles may be repaired when provider access returns.
    var titleNeedsRefresh = false
    // Informational provenance only; never restored as a save permission.
    var sourceUri: String? = null
    var recoveryError: String? = null
    var placeholder = true
    var revision = 0L
}
class EditorSessions(private val residentBudget:Long=64L*1024*1024) {
    val documents = mutableListOf<EditorSession>()
    private fun userBytes(d:UserData?)=(d?.text?.length ?: 0)*2L+(d?.properties?.size ?: 0)+16
    fun documentBytes(d:Document):Long=1024L+(d.header?.size ?: 0)+userBytes(d.data)+
        d.layers.sumOf {it.name.length*2L+(it.uuid?.size ?: 0)+userBytes(it.data)}+
        d.tags.sumOf {it.name.length*2L+it.color.size+userBytes(it.data)}+
        d.frames.sumOf {f->64L+f.palette.size*8L+f.paletteNames.values.sumOf {it.length*2L}+f.metadata.sumOf {it.second.size.toLong()}+f.cels.sumOf {c->if(c==null)0L else 64L+c.pixels.size*4L+userBytes(c.data)}}
    fun configure(session:EditorSession){
        session.engine.historyBudgetBytes=8L*1024*1024
        session.engine.validateCandidate={candidate->checkBudget(candidate,session.id)}
    }
    private fun checkBudget(candidate:Document?=null,replacing:Int?=null,newClipboard:Document?=null){
        val clip=newClipboard ?: clipboard
        val total=documents.filter {it.id!=replacing}.sumOf {documentBytes(it.engine.document)}+(candidate?.let(::documentBytes) ?: 0L)+(clip?.let(::documentBytes) ?: 0L)
        require(total<=residentBudget) { "Open documents and copied tag exceed the 64 MiB editing budget. Close a document or clear the copied tag; no work was changed." }
    }
    var activeId = 0
    var nextId = 1
    private var clipboard: Document? = null
    val active get() = documents.firstOrNull { it.id == activeId } ?: error("Create or open a drawing first")
    fun add(document: Document, title: String? = null, unsaved: Boolean = false): EditorSession {
        checkBudget(document,if(documents.size==1&&active.placeholder&&!active.engine.dirty)activeId else null)
        if(documents.size==1 && active.placeholder && !active.engine.dirty)documents.clear()
        require(documents.size < 8) { "Close a document before opening another (8 maximum)." }
        val session=EditorSession(nextId++)
        if(title!=null)session.title=title
        configure(session);session.placeholder=false;session.engine.replace(document,unsaved)
        documents.add(session);activeId=session.id
        return session
    }
    fun initializePlaceholder(text: String, allow: Boolean = true) {
        defaultUserData(mapOf("defaultUserData" to text))
        val session = documents.firstOrNull { it.id == activeId } ?: return
        if (!allow || text.isEmpty() || !session.placeholder || session.engine.dirty ||
            session.engine.document.data != null) return
        val candidate = session.engine.document.copyDeep().also { it.data = UserData(text = text) }
        checkBudget(candidate, session.id)
        session.engine.replace(candidate)
    }
    fun select(id: Int) { require(documents.any { it.id==id }) { "Document is no longer open" };activeId=id }
    fun close(id: Int,discard: Boolean=false) {
        val index=documents.indexOfFirst { it.id==id }
        require(index>=0) { "Document is no longer open" }
        require(!documents[index].engine.dirty || discard) { "Save this document or confirm discarding its unsaved changes." }
        documents.removeAt(index)
        if(activeId==id)activeId=if(documents.isEmpty())0 else documents[index.coerceAtMost(documents.lastIndex)].id
    }
    fun copyTag(index: Int) { val copy=TagTransfer.copy(active.engine.document,index);checkBudget(newClipboard=copy);clipboard=copy }
    fun clearClipboard(){clipboard=null}
    fun validateRecoveryCandidates(recovered:List<Document>,replacing:Set<Int>){
        val remaining=documents.filter {it.id !in replacing && !(documents.size==1 && it.placeholder && !it.engine.dirty)}
        val total=remaining.sumOf {documentBytes(it.engine.document)}+recovered.sumOf(::documentBytes)+(clipboard?.let(::documentBytes) ?: 0L)
        require(total<=residentBudget) { "Recovered documents exceed the 64 MiB editing budget. Existing documents and recovery files were retained." }
    }

    fun restoreDecoded(items:List<Pair<Int?,Document>>):List<EditorSession>{
        validateRecoveryCandidates(items.map {it.second},items.mapNotNull {it.first}.toSet())
        val staged=documents.filterNot {documents.size==1 && it.placeholder && !it.engine.dirty}.toMutableList()
        var next=nextId
        val restored=items.map { (oldId,doc)->
            val index=staged.indexOfFirst {it.id==oldId}
            val previous=if(index<0)null else staged[index]
            val id=previous?.id ?: oldId?.takeIf { it > 0 } ?: next++
            next=maxOf(next,id+1)
            val session=EditorSession(id,previous?.title ?: "Recovered $id")
            session.placeholder=false;session.engine.replace(doc,true);configure(session)
            if(index<0)staged.add(session)else staged[index]=session
            session
        }
        require(staged.size<=8) { "Close documents before recovering more (8 maximum)." }
        if(items.isEmpty())return restored
        documents.clear();documents.addAll(staged);nextId=next
        if(documents.none {it.id==activeId})activeId=restored.last().id
        return restored
    }
    fun pasteTag(after: Int? = null) {
        val section=clipboard ?: error("Copy a tag section first")
        active.engine.applyDocumentEdit { TagTransfer.paste(it,after ?: active.engine.frame,section) }
    }
    fun pasteTagAsNew() {
        val section=clipboard ?: error("Copy a tag section first")
        add(Aseprite.read(Aseprite.write(section)),section.tags.single().name,true)
    }
    fun state(recoveryAvailable: Boolean): Map<String,Any?> = (if(documents.isEmpty()) mapOf<String,Any?>(
        "width" to 0, "height" to 0, "frame" to 0, "layer" to 0, "depth" to 32,
        "dirty" to false, "canUndo" to false, "canRedo" to false,
        "recoveryAvailable" to recoveryAvailable, "pixels" to byteArrayOf(),
        "palette" to emptyList<Int>(), "layers" to emptyList<Any>(),
        "frames" to emptyList<Any>(), "tags" to emptyList<Any>(), "userData" to emptyMap<String,Any?>()
    ) else active.engine.state(recoveryAvailable)).toMutableMap().also {
        it["hasDocument"]=documents.isNotEmpty()
        it["documentId"]=activeId;it["hasTagClipboard"]=clipboard!=null;it["recoveryError"]=documents.firstOrNull {s -> s.id==activeId}?.recoveryError
        it["documents"]=documents.map { s -> mapOf("id" to s.id,"title" to s.title,"dirty" to s.engine.dirty,"recoveryError" to s.recoveryError,"active" to (s.id==activeId)) }
    }
}

