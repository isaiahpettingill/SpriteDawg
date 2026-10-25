# Compatibility and implementation

## Format support and preservation

The codec is plain Kotlin/JDK and independent of Android and Compose. It follows
https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md.

Supported: 32-bit RGBA, 16-bit grayscale/alpha, 8-bit indexed; raw/zlib image cels;
linked cels, signed cel positions, cel/layer opacity, visibility, layer UUIDs,
multiple layers/frames, frame timing, tags, modern/legacy palettes, and user data.
Indexed files retain native indices, transparent index, frame palettes, and depth.
Drawing maps to the nearest current palette entry; erasing uses the transparent
index. Indexed background layers follow Aseprite's opaque-background semantics. Eraser
selection offers explicit conversion to a normal layer, remapping the background
index to an identical existing/new palette entry before enabling transparency.
Conversion refuses a full palette without an identical replacement, preserving
all colors and source pixels. New palette entries use small patches so names
and metadata on existing entries remain intact.
Grayscale drawing converts RGB to luminance and preserves alpha. New documents
start in RGBA. Editing a linked cel detaches it so other frames keep their pixels.

Palette chunks (including names) and safe color profiles are retained. User data
text/color/property payloads remain associated with their objects, including linked
cels. Structural edits deliberately delete data belonging to deleted objects.
Adding/removing frames adjusts tag ranges; singleton tags disappear with their frame.

The application refuses unsupported files before replacing the active document:
groups, tilemaps/tilesets, non-normal blend modes, reference layers, per-cel z-order,
precise cel transforms, slices, external references, embedded ICC/custom-gamma
profiles, non-square pixel ratios, unknown chunks/flags, and unknown reserved data.
Refusal names the limitation and never opens the source for writing. Indexed files
without an explicit palette are refused because the creator's default palette
cannot be inferred safely. Nested property values are validated and copied verbatim;
external-reference-bearing files are refused. This is deliberately conservative.

Safety limits: 2048×2048 canvas, 4 Mi pixels per cel, 4096 frames, 256 layers,
16 Mi total decoded pixels, and 64 MiB files. A cel whose expanded bounds
would exceed the editing budget is displayed/saved but cannot be painted; the app
explains the limitation instead of changing that cel. Zlib output, lengths, chunk/frame
boundaries, indices, link targets, and strings are checked. Larger files receive
an error rather than uncontrolled allocations. Start with small game sprites;
this is not a large illustration editor.

## Tests and layout

`Document.kt`: buffers, compositing, drawing tools, history.
`Aseprite.kt`: bounded native reader/writer.
`UserProperties.kt`: typed user data validation and scalar editing.
`PixelView.kt`: Android Canvas and pointer handling.
`MainActivity.kt`: single-screen Compose controls, document picker, recovery.
`EditorDialogs.kt`: compact color, dimensions, tags, and user data dialogs.

JUnit tests cover headers, exact pixels/alpha, raw and compressed cels, layers,
frame timing, linked cels and detaching, positions, tags, text/color/typed user data,
indexed/grayscale round trips, upstream sprites, unsupported features, every byte
truncation of an encoded project, mutated input, fill/lines, and undo/redo.


## Flutter migration

The current UI is in `lib/main.dart`, `lib/editor.dart` and `lib/pixel_canvas.dart`.
Android platform file handling and the Kotlin codec now build from `android/app/`;
the previous Compose UI in `app/` is reference-only. Linux uses the port under
`lib/engine/` with native file dialogs and atomic local-file replacement in
`lib/platform/desktop_backend.dart`. Both preserve the existing format refusal
policy; see `INTEROP_REVIEW.md` for independent implementation comparisons and
explicit remaining verification limits. PNG export is intentionally separate from
Aseprite saving. Linux recovery lives in the platform application-support folder.
