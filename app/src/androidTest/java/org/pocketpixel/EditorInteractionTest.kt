package org.pocketpixel

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Exercises the actual Compose controls and touch interop, not only the drawing functions. */
class EditorInteractionTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    private lateinit var editor: Editor

    private fun start(d: Document = Document.create(16, 16)) {
        ui.waitForIdle()
        if (ui.onAllNodesWithText("Discard").fetchSemanticsNodes().isNotEmpty()) {
            ui.onNodeWithText("Discard").performClick()
        }
        ui.runOnIdle {
            editor = ViewModelProvider(ui.activity)[Editor::class.java]
            editor.replace(d)
        }
        ui.waitForIdle()
    }

    private fun tool(name: String) {
        ui.onNodeWithTag("tool-$name").performClick()
        ui.waitForIdle()
    }

    private fun tap() {
        ui.onNodeWithTag("pixelCanvas").performTouchInput { click(center) }
        ui.waitForIdle()
    }

    private fun drag() {
        ui.onNodeWithTag("pixelCanvas").performTouchInput {
            val span = minOf(width, height) * 0.22f
            swipe(center - Offset(span, span), center + Offset(span, span), 250)
        }
        ui.waitForIdle()
    }

    private fun pixels() = editor.doc.resolved(editor.frame, editor.layer)?.pixels ?: IntArray(0)

    @Test
    fun pencilEraserAndUndoUseSelectedControls() {
        start()
        tool("Pencil")
        drag()
        ui.runOnIdle { assertTrue("Pencil must modify pixels", pixels().any { it ushr 24 != 0 }) }
        tool("Eraser")
        drag()
        ui.runOnIdle {
            assertTrue("Eraser must clear the same stroke", pixels().all { it ushr 24 == 0 })
        }
        ui.onNodeWithText("↶").performClick()
        ui.runOnIdle { assertTrue("Undo must restore stroke", pixels().any { it ushr 24 != 0 }) }
    }

    @Test
    fun fillAndEyedropperUseSelectedControls() {
        start()
        ui.runOnIdle { editor.color = 0xffff3344.toInt() }
        tool("Fill")
        tap()
        ui.runOnIdle {
            assertEquals(256, pixels().count { it == 0xffff3344.toInt() })
            editor.color = 0xff000000.toInt()
        }
        val rendered = ui.onNodeWithTag("pixelCanvas").captureToImage().toPixelMap()
        val centerColor = rendered[rendered.width / 2, rendered.height / 2]
        assertTrue(
            "The visible canvas must repaint with fill color",
            centerColor.red > 0.9f && centerColor.green < 0.4f,
        )
        tool("Pick")
        tap()
        ui.runOnIdle { assertEquals(0xffff3344.toInt(), editor.color) }
    }

    @Test
    fun lineAndRectangleCommitAfterDrag() {
        start()
        tool("Line")
        drag()
        ui.runOnIdle { assertTrue(pixels().count { it ushr 24 != 0 } > 1) }
        ui.onNodeWithText("↶").performClick()
        tool("Rect")
        drag()
        ui.runOnIdle { assertTrue(pixels().count { it ushr 24 != 0 } > 4) }
    }

    @Test
    fun openedDocumentSelectsVisibleTopLayer() {
        val d = Document.create(16, 16)
        d.layers[0].visible = false
        d.layers.add(Layer("Foreground"))
        d.frames[0].cels.add(null)
        start(d)
        tap()
        ui.runOnIdle {
            assertEquals(1, editor.layer)
            assertTrue(pixels().any { it ushr 24 != 0 })
        }
    }

    @Test
    fun panDoesNotPaint() {
        start()
        tool("Pan")
        drag()
        ui.runOnIdle {
            assertTrue(pixels().all { it ushr 24 == 0 })
            assertFalse(editor.dirty)
        }
    }

    @Test
    fun secondFingerCancelsDrawingAndPansWithoutInk() {
        start()
        tool("Pencil")
        ui.onNodeWithTag("pixelCanvas").performTouchInput {
            down(0, center - Offset(40f, 0f))
            down(1, center + Offset(40f, 0f))
            moveTo(0, center - Offset(60f, -15f))
            moveTo(1, center + Offset(60f, 15f))
            up(1)
            up(0)
        }
        ui.runOnIdle {
            assertFalse(editor.dirty)
            assertTrue(pixels().all { it ushr 24 == 0 })
        }
    }

    @Test
    fun selectingToolStopsPlayback() {
        start()
        ui.onNodeWithText("Play").performClick()
        tool("Pencil")
        ui.runOnIdle { assertFalse(editor.playing) }
        tap()
        ui.runOnIdle { assertTrue(pixels().any { it ushr 24 != 0 }) }
    }

    @Test
    fun indexedBackgroundCanBeConvertedAndErased() {
        val d = Document.create(16, 16)
        d.depth = 8
        d.layers[0].flags = 11
        d.frames[0].palette = intArrayOf(0xffff3344.toInt(), 0xff00ff00.toInt())
        d.editable(0, 0)
        start(d)
        tool("Eraser")
        ui.onNodeWithText("Convert layer").performClick()
        drag()
        ui.runOnIdle {
            assertEquals(0, editor.doc.layers[0].flags and 8)
            assertTrue(editor.doc.composite(0).any { it ushr 24 == 0 })
            assertTrue(editor.doc.composite(0).any { it == 0xffff3344.toInt() })
        }
    }
}
