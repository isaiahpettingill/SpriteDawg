package org.pocketpixel
import org.junit.Assert.*
import org.junit.Test

class PaletteEditingTest {
 @Test fun namedRgbaPresetsKeepExactArgbAndNamesAcrossFrames() {
  val e = indexed()
  e.edit(mapOf("action" to "convertMode", "depth" to 32))
  e.replace(e.document.copyDeep())
  val before = Aseprite.write(e.document)
  val pixels = (0..1).map { e.document.composite(it) }
  val colors = listOf(0xffc08040L, 0x80c08040L, 0x20c08040L, 0x00112233L)
  val names = mutableListOf("Terre brûlée", "Glaze 50%", "Glaze 12.5%", "")
  val expectedNames = mapOf(0 to names[0], 1 to names[1], 2 to names[2])
  e.edit(mapOf("action" to "palettePreset", "colors" to colors, "names" to names))
  val reopened = Aseprite.read(Aseprite.write(e.document))
  for (f in 0..1) {
   assertArrayEquals(colors.map { it.toInt() }.toIntArray(), e.document.frames[f].palette)
   assertEquals(expectedNames, e.document.frames[f].paletteNames)
   assertArrayEquals(colors.map { it.toInt() }.toIntArray(), reopened.frames[f].palette)
   assertEquals(expectedNames, reopened.frames[f].paletteNames)
   assertArrayEquals(pixels[f], reopened.composite(f))
  }
  e.undo()
  assertArrayEquals(before, Aseprite.write(e.document))
  assertEquals(false, e.state(false)["canUndo"])
  e.redo()
  assertEquals(expectedNames, e.document.frames[1].paletteNames)
  names[0] = "Changed input"
  e.document.frames[0].paletteNames[0] = "Changed frame"
  assertEquals("Terre brûlée", e.document.frames[1].paletteNames[0])
 }
 @Test fun namedIndexedPresetsKeepSemitransparentFrameColorsAndUndo() {
  val e = EditorEngine()
  e.replace(Document(5, 1, mutableListOf(Layer("Ink"), Layer("Background", flags = 11)), mutableListOf(
   Frame(palette = intArrayOf(0xff3c2a18.toInt(), 0x80aabbcc.toInt(), 0xffaabbcc.toInt(), 0x20aabbcc, 0),
    paletteNames = mutableMapOf(1 to "old glaze"), cels = mutableListOf(
     Cel(0, 0, 5, 1, intArrayOf(1, 2, 3, 0, 4)), Cel(0, 0, 5, 1, intArrayOf(1, 2, 3, 0, 4)))),
   Frame(palette = intArrayOf(0xff3c2a18.toInt(), 0x20aabbcc, 0x80aabbcc.toInt(), 0xffaabbcc.toInt(), 0),
    paletteNames = mutableMapOf(1 to "old light glaze"), cels = mutableListOf(
     Cel(0, 0, 0, 0, intArrayOf(), link = 0, data = UserData(text = "linked-glaze")), null))
  ), depth = 8))
  val before = Aseprite.write(e.document)
  val pixels = (0..1).map { e.document.composite(it) }
  val colors = listOf(0xffaabbccL, 0x80aabbccL, 0x20aabbccL, 0xff3c2a18L, 0x00112233L)
  val names = listOf("Solid", "Glaze 50%", "Glaze 12.5%", "Ground", "Hidden RGB")
  val expectedNames = names.mapIndexed { i, name -> i to name }.toMap()
  e.edit(mapOf("action" to "palettePreset", "colors" to colors, "names" to names, "remap" to true))
  assertEquals(8, e.document.depth)
  assertEquals(5, e.document.transparentIndex)
  assertArrayEquals(intArrayOf(1, 0, 2, 5, 5), e.document.frames[0].cels[0]!!.pixels)
  assertArrayEquals(intArrayOf(1, 0, 2, 3, 5), e.document.frames[0].cels[1]!!.pixels)
  assertArrayEquals(intArrayOf(2, 1, 0, 5, 5), e.document.frames[1].cels[0]!!.pixels)
  assertNull(e.document.frames[1].cels[0]!!.link)
  val reopened = Aseprite.read(Aseprite.write(e.document))
  assertEquals("linked-glaze", reopened.frames[1].cels[0]!!.data!!.text)
  for (f in 0..1) {
   assertEquals(expectedNames, e.document.frames[f].paletteNames)
   assertArrayEquals((colors + 0L).map { it.toInt() }.toIntArray(), reopened.frames[f].palette)
   assertEquals(expectedNames, reopened.frames[f].paletteNames)
   assertArrayEquals(pixels[f], reopened.composite(f))
  }
  e.undo()
  assertArrayEquals(before, Aseprite.write(e.document))
  assertEquals(false, e.state(false)["canUndo"])
  e.redo()
  assertEquals(expectedNames, e.document.frames[1].paletteNames)
  assertArrayEquals(intArrayOf(2, 1, 0, 5, 5), e.document.frames[1].cels[0]!!.pixels)
 }
 @Test fun invalidPresetNamesPreserveArtworkAndUndoRedoHistory() {
  for (e in listOf(EditorEngine(), indexed())) {
   val before = Aseprite.write(e.document)
   val args = mapOf("action" to "palettePreset", "colors" to listOf(0x80abcdefL, 0xffabcdefL), "names" to listOf("Glaze", "Solid"), "remap" to true)
   e.edit(args)
   e.undo()
   e.saved()
   for (names in listOf(null, "not a list", emptyList<String>(), listOf("Only one"), listOf("One", "Two", "Extra"),
    listOf(1, "Two"), listOf("One", null), listOf("a".repeat(65536), "Two"), listOf("é".repeat(32768), "Two"))) {
    try { e.edit(args + ("names" to names)); fail("must reject") } catch (_: IllegalArgumentException) {}
    assertArrayEquals(before, Aseprite.write(e.document))
    assertEquals(false, e.state(false)["canUndo"])
    assertEquals(true, e.state(false)["canRedo"])
    assertFalse(e.dirty)
   }
   e.redo()
   assertEquals(mapOf(0 to "Glaze", 1 to "Solid"), e.document.frames[0].paletteNames)
  }
 }
 @Test fun presetNamesAcceptUtf8ByteLimitAndEmptyUnnamedSlots() {
  val name = "€".repeat(21845) // Exactly 65535 UTF-8 bytes.
  for (e in listOf(EditorEngine(), indexed())) {
   val before = Aseprite.write(e.document)
   e.edit(mapOf("action" to "palettePreset", "colors" to listOf(0x80446688L, 0xff446688L), "names" to listOf(name, ""), "remap" to true))
   val reopened = Aseprite.read(Aseprite.write(e.document))
   for (frame in reopened.frames) assertEquals(mapOf(0 to name), frame.paletteNames)
   e.undo()
   assertArrayEquals(before, Aseprite.write(e.document))
  }
 }
 @Test fun rgbaPresetChangesSwatchesButNotArtworkOrLinks() {
  val e = indexed()
  e.edit(mapOf("action" to "convertMode", "depth" to 32))
  e.document.frames[1].cels[0] = Cel(0, 0, 0, 0, intArrayOf(), link = 0, data = UserData(text = "linked-rgba"))
  e.document.frames[0].metadata.add(0x2007 to ByteArray(16))
  e.replace(Aseprite.read(Aseprite.write(e.document)))
  val before = Aseprite.write(e.document)
  val pixels = (0..1).map { e.document.composite(it) }
  val colors = listOf(0xff123456L, 0x80765432L)
  assertTrue(e.document.frames[0].metadata.any { it.first == 0x2019 })
  e.edit(mapOf("action" to "palettePreset", "colors" to colors))
  assertEquals(32, e.document.depth)
  assertEquals(0, e.document.frames[1].cels[0]!!.link)
  assertEquals(colors.map { it.toInt() }, e.document.palette)
  for (f in 0..1) {
   assertArrayEquals(colors.map { it.toInt() }.toIntArray(), e.document.frames[f].palette)
   assertTrue(e.document.frames[f].paletteNames.isEmpty())
   assertTrue(e.document.frames[f].palettePatches.isEmpty())
   assertFalse(e.document.frames[f].metadata.any { it.first in listOf(4, 17, 0x2019) })
   assertArrayEquals(pixels[f], e.document.composite(f))
  }
  assertEquals(0x2007, e.document.frames[0].metadata.single().first)
  val reopened = Aseprite.read(Aseprite.write(e.document))
  assertEquals("linked-rgba", reopened.frames[1].cels[0]!!.data!!.text)
  assertEquals("sprite-meta", reopened.data!!.text)
  for (f in 0..1) {
   assertArrayEquals(colors.map { it.toInt() }.toIntArray(), reopened.frames[f].palette)
   assertTrue(reopened.frames[f].paletteNames.isEmpty())
   assertArrayEquals(pixels[f], reopened.composite(f))
  }
  e.undo()
  assertArrayEquals(before, Aseprite.write(e.document))
  assertEquals(false, e.state(false)["canUndo"])
  e.redo()
  e.document.frames[0].palette[0] = 0
  assertEquals(0xff123456.toInt(), e.document.frames[1].palette[0])
 }
 @Test fun indexedPresetResolvesFrameColorsAndPreservesBackgroundTransparency() {
  val e = indexed()
  e.document.frames[1].palette += 0xff999999.toInt()
  e.document.frames[1].cels[0]!!.opacity = 128
  val before = Aseprite.write(e.document)
  val pixels = (0..1).map { e.document.composite(it) }
  val colors = listOf(0xff0000ffL, 0xffff0000L, 0xff102030L, 0xff00ff00L)
  e.edit(mapOf("action" to "palettePreset", "colors" to colors, "remap" to true))
  assertEquals(8, e.document.depth)
  assertEquals(4, e.document.transparentIndex)
  assertArrayEquals(intArrayOf(1, 4), e.document.frames[0].cels[0]!!.pixels)
  assertArrayEquals(intArrayOf(2, 3), e.document.frames[0].cels[1]!!.pixels)
  assertArrayEquals(intArrayOf(0, 4), e.document.frames[1].cels[0]!!.pixels)
  assertNull(e.document.frames[1].cels[0]!!.link)
  assertEquals(128, e.document.frames[1].cels[0]!!.opacity)
  assertEquals("linked-meta", e.document.frames[1].cels[0]!!.data!!.text)
  assertEquals(11, e.document.layers[1].flags)
  val reopened = Aseprite.read(Aseprite.write(e.document))
  for (f in 0..1) {
   assertArrayEquals((colors + 0L).map { it.toInt() }.toIntArray(), reopened.frames[f].palette)
   assertTrue(reopened.frames[f].paletteNames.isEmpty())
   assertArrayEquals(pixels[f], reopened.composite(f))
  }
  e.undo()
  assertArrayEquals(before, Aseprite.write(e.document))
  assertEquals(false, e.state(false)["canUndo"])
  e.redo()
  assertArrayEquals(intArrayOf(0, 4), e.document.frames[1].cels[0]!!.pixels)
 }
 @Test fun presetQuantizationIncludesAlphaAndResolvesTiesDeterministically() {
  val e = EditorEngine()
  e.replace(Document(4, 1, mutableListOf(Layer("Ink")), mutableListOf(
   Frame(palette = intArrayOf(0, 0xff101010.toInt(), 0x80101010.toInt(), 0xff808080.toInt()),
    cels = mutableListOf(Cel(0, 0, 4, 1, intArrayOf(0, 1, 2, 3))))
  ), depth = 8))
  e.edit(mapOf("action" to "palettePreset", "colors" to listOf(0xff101010L, 0x80101010L, 0xff7f8080L, 0xff818080L), "remap" to true))
  assertArrayEquals(intArrayOf(4, 0, 1, 2), e.document.frames[0].cels[0]!!.pixels)
 }
 @Test fun invalidPresetsAndUnconfirmedRemapsDoNotChangeHistory() {
  val e = EditorEngine()
  val before = Aseprite.write(e.document)
  for (colors in listOf(null, "not a list", emptyList<Int>(), List(257) { 0 }, listOf(-1), listOf(0x100000000L), listOf(1.0), listOf("ffffff"), listOf(null))) {
   try { e.edit(mapOf("action" to "palettePreset", "colors" to colors)); fail("must reject") }
   catch (_: IllegalArgumentException) {}
   assertArrayEquals(before, Aseprite.write(e.document))
   assertEquals(false, e.state(false)["canUndo"])
   assertFalse(e.dirty)
  }
  val i = indexed()
  val indexedBefore = Aseprite.write(i.document)
  for (args in listOf(
   mapOf("colors" to listOf(0xff000000L)),
   mapOf("colors" to listOf(0xff000000L), "remap" to false),
   mapOf("colors" to listOf(0xff000000L), "remap" to "true"),
   mapOf("colors" to List(256) { 0xff000000L }, "remap" to true)
  )) {
   try { i.edit(mapOf("action" to "palettePreset") + args); fail("must reject") }
   catch (_: IllegalArgumentException) {}
   assertArrayEquals(indexedBefore, Aseprite.write(i.document))
   assertEquals(false, i.state(false)["canUndo"])
  }
 }
 @Test fun presetAcceptsMaximumRgbaAndIndexedPaletteSizes() {
  val e = EditorEngine()
  val colors = List(256) { 0xff000000L or it.toLong() }
  e.edit(mapOf("action" to "palettePreset", "colors" to colors))
  assertArrayEquals(colors.map { it.toInt() }.toIntArray(), Aseprite.read(Aseprite.write(e.document)).frames[0].palette)
  val i = indexed()
  i.edit(mapOf("action" to "palettePreset", "colors" to colors.take(255), "remap" to true))
  assertEquals(255, i.document.transparentIndex)
  assertEquals(256, Aseprite.read(Aseprite.write(i.document)).frames[0].palette.size)
 }
 @Test fun presetRejectsLinkedExpansionBeyondDecodedPixelBudget() {
  val e = EditorEngine()
  val d = Document(2048, 2048, mutableListOf(Layer("Ink")), (0..4).map { f ->
   Frame(palette = intArrayOf(0xff000000.toInt()), cels = mutableListOf(
    if (f == 0) Cel(0, 0, 2048, 2048, IntArray(Document.MAX_PIXELS))
    else Cel(0, 0, 0, 0, intArrayOf(), link = 0)))
  }.toMutableList(), depth = 8)
  e.replace(d)
  try { e.edit(mapOf("action" to "palettePreset", "colors" to listOf(0xff000000L), "remap" to true)); fail("must reject") }
  catch (_: IllegalArgumentException) {}
  assertSame(d, e.document)
  assertEquals(0, e.document.frames[4].cels[0]!!.link)
  assertEquals(false, e.state(false)["canUndo"])
 }
 @Test fun presetValidatorFailurePreservesDocumentAndRedoHistory() {
  val e = indexed()
  val args = mapOf("action" to "palettePreset", "colors" to listOf(0xff000000L, 0xffffffffL), "remap" to true)
  e.edit(args)
  e.undo()
  val before = Aseprite.write(e.document)
  e.validateCandidate = { throw IllegalArgumentException("Test rejection") }
  try { e.edit(args); fail("must reject") } catch (_: IllegalArgumentException) {}
  assertArrayEquals(before, Aseprite.write(e.document))
  assertEquals(false, e.state(false)["canUndo"])
  assertEquals(true, e.state(false)["canRedo"])
  e.validateCandidate = null
  e.redo()
  assertEquals(2, e.document.transparentIndex)
 }
 private fun indexed():EditorEngine {
  val e=EditorEngine()
  e.replace(Document(2,1,mutableListOf(Layer("Ink"),Layer("Background",flags=11)),mutableListOf(
   Frame(cels=mutableListOf(Cel(0,0,2,1,intArrayOf(1,0),data=UserData(text="cel-meta")),Cel(0,0,2,1,intArrayOf(0,2))),palette=intArrayOf(0xff102030.toInt(),0xffff0000.toInt(),0xff00ff00.toInt()),paletteNames=mutableMapOf(0 to "transparent",1 to "primary",2 to "leaf")),
   Frame(duration=125,cels=mutableListOf(Cel(0,0,0,0,intArrayOf(),link=0,data=UserData(text="linked-meta")),null),palette=intArrayOf(0xffabcdef.toInt(),0xff0000ff.toInt(),0xffffff00.toInt()),paletteNames=mutableMapOf(0 to "hole",1 to "water",2 to "sun"))
  ),depth=8,transparentIndex=0,data=UserData(text="sprite-meta")))
  return e
 }
 @Test fun reorderRetainsAppearanceNamesLinksAndUndo(){val e=indexed();val before=Aseprite.write(e.document);val pixels=(0..1).map{e.document.composite(it)};e.edit(mapOf("action" to "paletteMove","index" to 0,"to" to 2));assertEquals(2,e.document.transparentIndex);assertEquals(0,e.document.frames[1].cels[0]!!.link);assertEquals("water",e.document.frames[1].paletteNames[0]);val d=Aseprite.read(Aseprite.write(e.document));for(f in 0..1)assertArrayEquals(pixels[f],d.composite(f));assertEquals("linked-meta",d.frames[1].cels[0]!!.data!!.text);e.undo();assertArrayEquals(before,Aseprite.write(e.document));e.redo();assertEquals(2,e.document.transparentIndex)}
 @Test fun editIsFrameLocalAndRoundTripsNames(){val e=indexed();e.select(mapOf("frame" to 1));e.edit(mapOf("action" to "paletteEdit","index" to 1,"color" to 0xff223344L,"name" to "new water"));val d=Aseprite.read(Aseprite.write(e.document));assertEquals(0xffff0000.toInt(),d.frames[0].palette[1]);assertEquals(0xff223344.toInt(),d.frames[1].palette[1]);assertEquals("new water",d.frames[1].paletteNames[1]);assertEquals("primary",d.frames[0].paletteNames[1])}
 @Test fun addAndRemoveKeepTimelineAndExplicitMapping(){val e=indexed();e.edit(mapOf("action" to "paletteAdd","color" to 0x80445566L,"name" to "glow"));assertEquals("glow",Aseprite.read(Aseprite.write(e.document)).frames[1].paletteNames[3]);e.edit(mapOf("action" to "paletteRemove","index" to 1,"replacement" to 2));assertArrayEquals(intArrayOf(1,0),e.document.frames[0].cels[0]!!.pixels);assertEquals(0,e.document.frames[1].cels[0]!!.link);assertEquals("sun",e.document.frames[1].paletteNames[1])}
 @Test fun invalidMutationsDoNotTouchHistory(){val e=indexed();val before=Aseprite.write(e.document);for(a in listOf(mapOf("action" to "paletteRemove","index" to 0,"replacement" to 1),mapOf("action" to "paletteRemove","index" to 1,"replacement" to 0),mapOf("action" to "paletteMove","index" to 1.5,"to" to 2),mapOf("action" to "paletteEdit","index" to 1,"color" to -1,"name" to ""))){try{e.edit(a);fail("must reject")}catch(_:IllegalArgumentException){};assertArrayEquals(before,Aseprite.write(e.document));assertEquals(false,e.state(false)["canUndo"])}}
 @Test fun rgbaConversionResolvesPerFrameLinksAndMetadata(){val e=indexed();val before=Aseprite.write(e.document);val pixels=(0..1).map{e.document.composite(it)};e.edit(mapOf("action" to "convertMode","depth" to 32));val d=Aseprite.read(Aseprite.write(e.document));assertNull(d.frames[1].cels[0]!!.link);assertEquals("linked-meta",d.frames[1].cels[0]!!.data!!.text);for(f in 0..1)assertArrayEquals(pixels[f],d.composite(f));e.undo();assertArrayEquals(before,Aseprite.write(e.document))}
 @Test fun indexedConversionReservesTransparencyAndKeepsOpaqueBlack(){val e=EditorEngine();val d=Document(3,1,mutableListOf(Layer("Ink")),mutableListOf(Frame(cels=mutableListOf(Cel(0,0,3,1,intArrayOf(0xff000000.toInt(),0,0x80112233.toInt()))),palette=intArrayOf(0xff000000.toInt(),0xff112233.toInt(),0x80112233.toInt()),paletteNames=mutableMapOf(0 to "black"))));e.replace(d);val before=Aseprite.write(e.document);e.edit(mapOf("action" to "convertMode","depth" to 8));assertEquals(3,e.document.transparentIndex);assertArrayEquals(intArrayOf(0,3,2),e.document.frames[0].cels[0]!!.pixels);assertArrayEquals(intArrayOf(0xff000000.toInt(),0,0x80112233.toInt()),Aseprite.read(Aseprite.write(e.document)).composite(0));e.undo();assertArrayEquals(before,Aseprite.write(e.document))}
}
