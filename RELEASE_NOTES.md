# SpriteDawg 0.3 — visual tags and multi-document workspaces

SpriteDawg is now a Flutter pixel-art editor for Android and Linux, focused on drawing on the go. Free, open source, offline: no accounts, ads, analytics, or Android internet permission.

## Palette controls

- 25 offline built-in palettes: all prior retro presets plus Monokai (Pygments), four Catppuccin flavors, TIC-80/Sweetie16, DawnBringer16 and original Gaem-64, Materials, Characters and Food palettes. AAP-64 is replaced by an independently authored alternative, not copied.
- Named opaque/translucent ramps, checkerboard previews and exact opacity labels. Materials include gold/silver/copper/bronze/steel and diamond/ruby/emerald/sapphire/amethyst.
- Save the current palette into My palettes, edit personal presets without altering artwork, or save a customizable copy of a built-in. Local persistence keeps ordered ARGB and names across restarts; duplicate names never silently overwrite.
- Full third-party license notices are available in the palette browser.
- Preset application is one undo step. RGB/grayscale artwork is unchanged; indexed documents require explicit nearest-color remapping with a reserved transparent slot across all frames. Existing palettes can be restored with Undo.
- The presets are a curated redistributable selection, not every palette bundled by Aseprite or LibreSprite; see `docs/PALETTE_SOURCES.md`.

- Brush color uses an alpha-aware color swatch; the eyedropper icon only samples the canvas.
- Compact palette dialog with **Add current color** and **Edit selected color**. Existing exact colors are selected without adding duplicate entries; explicit indexed selections retain their index.
- Naming, reordering, removing, color-mode conversion, and undo/redo live under **Palette options**. Removal and mode conversion retain their confirmation safeguards.

## Drawing and animation

- Long-stroke and effect previews remain visible until the committed canvas image is decoded, including when switching to two-finger navigation. The image handoff retires the matching preview atomically to avoid translucent double-paint flashes.

- Touch-first pencil, eraser, fill, eyedropper, line, rectangle, and ellipse tools.
- Two-finger pan/zoom preserves the drawn stroke segment; one-finger Pan and Fit are also available.
- Undo/redo, brush sizes, palette and color selection, layers, opacity, animation frames and timing, tags, playback, grid, and onion skin.
- Aseprite RGB, indexed, and grayscale/alpha editing with metadata preservation, including user-data text and existing typed properties. Unsupported rendering features are refused rather than silently flattened.
- Android document picker, Linux file dialogs, straight-alpha PNG export, and local recovery after completed edits.
- New SpriteDawg icon and Linux x64/ARM64 application bundles.

## Choose your download

- **Pixel 8 / GrapheneOS and most modern Android phones:** `android-arm64-v8a.apk`.
- **Older 32-bit ARM Android devices:** `android-armeabi-v7a.apk`.
- **Android x86-64 devices:** `android-x86_64.apk`.
- **Linux computers:** `linux-x64.tar.gz`; **ARM64 Linux phones/devices:** `linux-arm64.tar.gz`.

Android requires Android 10 or newer. Install just the APK matching your device. Production APKs retain `org.pocketpixel` and use the existing permanent signing key; development `.debug` builds remain separate and are not release assets. Existing production installations can update when signed with that same key. Export important projects before replacing or uninstalling any differently signed older build; uninstalling deletes app-private recovery.

Extract the entire Linux archive and run `spritedawg` from its extracted directory; its bundled `lib/` and `data/` directories are required. Linux bundles target Ubuntu 24.04-class systems with GTK 3 and a compatible glibc; ARM64 does not guarantee compatibility with every mobile Linux distribution.

`SHA256SUMS` contains checksums using asset basenames. Download it beside the assets you want to verify, then use `sha256sum --check --ignore-missing SHA256SUMS`.

The release is gated on Flutter tests/analyzer, native codec/interoperability tests and lint, Android emulator interaction tests, Linux builds on both architectures, and verified production signing. See the repository's compatibility documentation for format limits; this is not complete Aseprite desktop feature parity.

## New in the 0.3 series

- See frame thumbnails while tagging, adjust ranges/rename inline, duplicate tags, and choose static variant browsing or animation playback.
- Open up to eight documents with independent undo/save/recovery; copy whole tagged frame sections between compatible documents, or paste as a new document without lossy conversion.
- Roomier desktop/tablet workspace and larger play/pause controls.
- Filled rectangles/ellipses, two-color gradient flood fill, spray, alpha-aware blur, jumble, and horizontal/vertical symmetry.
- Indexed conversion and named palette swatches with exact index selection, add/edit/reorder/remove with explicit remapping and undo.

Tags remain contiguous Aseprite tags. Clipboard copies one selected tag, not overlapping tags. Mismatched canvas/depth/layer schemas are refused rather than silently converted. Physical Pixel/GrapheneOS/Linux phone validation is not claimed.

Every successful trusted push/merge to main now publishes automatically after all checks, Linux builds, and permanent-signature verification pass. No commit marker is needed. Version names use the release series plus the immutable workflow run number; retries reuse the same tag. Existing tags/assets are never overwritten. PR and tag pushes cannot publish.
