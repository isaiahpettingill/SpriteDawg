# SpriteDawg

<img src="art/spritedawg.svg" width="96" alt="SpriteDawg pixel dog icon">

An offline, touch-first **Flutter** pixel-art editor for Android and Linux phones.
The goal is simple: open a sprite, draw comfortably on the go, and keep your work.
MIT licensed, no ads, accounts, tracking, networking or broad Android storage permission.

## Draw

- Pencil, eraser, flood fill, eyedropper, line, outlined/filled rectangles and
  ellipses, dispersed spray, soft airbrush, blur, jumble and pan. The eraser has its own eraser icon.
- Long-hold a toolbar group to choose a subtool (right-click or the Menu key on desktop).
  Tap to use its last-selected tool; groups include ink, fill/gradient, shapes and effects.
  Filled rectangles/ellipses live with the outline shapes. Eight touch-sized group buttons
  wrap on very narrow phones rather than hiding tools in a long scrolling strip.
- The texture group includes **Bark**: irregular vertical grooves, lit ridges and
  occasional knots, using perceptually related shades from your chosen palette.
  Its grain is canvas-anchored throughout a gesture, including bends and repeated
  dabs; brush size scales the grain. It shares the texture tools' live preview,
  symmetry, exact indexed-color handling and single-step undo.
- **Leaves** in the texture group paints overlapping pointed leaves with dark
  interiors and lighter rims, using related colors from the current palette.
  Its seeded canopy stays anchored across overlapping dabs and bends; brush size
  scales the leaves. Like Bark it preserves exact indexed colors and palette alpha.
- **Splatter** in the ink/brush group scatters differently sized paint droplets.
  RGB droplets use the current color with varied opacity up to its selected alpha,
  blended source-over once per stroke. Unlike Spray, holding still does not build
  up. Indexed mode uses the exact selected palette entry and its alpha instead
  of synthesizing off-palette transparency. Both new brushes support live preview,
  mirrored strokes, per-tool sizes and single-step undo.
  See [rendered examples and verification](docs/BRUSHES.md).
- The dedicated **Gradient** subtool paints a linear gradient across the **whole active
  layer's canvas area**. Choose Start and End colors (including alpha), then drag to set
  direction and endpoint positions; outside the endpoints the respective color is clamped.
  A tap without a drag does nothing. It blends source-over, is one undo, and ignores brush
  size/symmetry. Indexed and grayscale results follow their mode's color mapping.
- Bucket fill's existing two-color horizontal/vertical gradients stay inside the connected fill region.
  Spray has adjustable density; blur/jumble have strength controls. Random tools
  use a fixed seed per gesture, and the entire gesture is one undo step.
- Horizontal/vertical symmetry mirrors around the canvas center. Center-line
  pixels are not applied repeatedly. In indexed mode, gradients and blur map
  results to the current palette; jumble moves native pixel indices.
- One finger/stylus draws; two fingers pan/pinch. Adding a second finger **keeps**
  the drawn segment and switches to navigation until all fingers lift.
- Per-tool brush sizes, visual HSV/alpha color picker, palette, grid, previous-frame onion skin and Fit.
- Spray and airbrush build up while held. Brush effects preview the actual engine
  result before release; the gesture remains one undo step. RGB transparency blends
  source-over without repeatedly darkening overlapping ordinary brush stamps.
- Undo/redo; visible/editable layer safeguards; layers, opacity and ordering.
- Compact frame navigation, duplication and animation playback with direction/repeat tags.
  Opening **Frames** brings the current frame into view. Set timing through
  **Frame options → Duration…**, or long-press/right-click a frame; timing stays
  out of the strip so there is more room for drawing.
- Visual tag editing keeps frame thumbnails visible with the selected range and
  current frame marked. Rename, adjust endpoints or duplicate quickly; browse tile
  variants without starting playback, or explicitly preview an animation. Tags
  remain generic, contiguous Aseprite ranges, not new incompatible tag types.
- Sprite/layer/cel/tag user-data text; existing binary typed-property payloads remain
  attached to their original objects. Unsupported advanced features are refused,
  rather than silently flattened.
- Aseprite open/save/save-as; offline PNG, GIF, APNG, WebP, QOI and AVIF export, plus PNG spritesheets with JSON. Exports flatten visible layers without changing the project.
- Debounced **internal drafts** for new, imported and edited documents. Android
  uses app-private files, Linux application support, and the browser IndexedDB—not
  cache or temporary storage. **Internal drafts…** lists named, dated copies;
  **Keep draft and close** leaves one available without keeping its tab open.
  Recovery always opens an **unsaved copy**, never an old writable save path.
  A damaged latest snapshot falls back to its previous validated generation, and
  a damaged draft does not prevent opening its neighbors. Storage failures are
  shown with a Save a copy action; they never count as successful autosaves.

Android uses the system document picker. Linux uses native GTK file dialogs.
Android tabs and internal drafts use the document provider's filename, not its
opaque URI ID. Older URI-ID draft labels are repaired when the original provider
is accessible; recovery still opens an unsaved copy without restoring a save grant.
Linux also supports pointer-wheel zoom, right-drag pan, Ctrl-Z/Y, Ctrl-Shift-Z,
Ctrl-S/O, and B/E/G/I/H tool shortcuts. Controls remain usable in narrow portrait
windows; desktop packaging declares mobile support to Linux phone shells.

## Documents, tags and palettes

Open up to eight documents in tabs with independent selection, undo, save targets
and recovery snapshots. Closing unsaved work requires explicit confirmation. On
roomier tablet/desktop windows, tools, canvas, layers and frame/tag workspace remain
visible together; compact phones use the same features in adaptive panels.

Copy a whole tag section and paste after the current frame in this or another open
document. Frame timing, tag/cel/layer metadata and per-frame indexed palettes are
retained; linked cels become self-contained within the copied section. Paste is one
undo transaction and never edits the source. Incompatible canvas dimensions, color
modes, transparent indices, layer schemas or profiles are refused rather than
silently flattened or renamed. **Paste as new document** is the safe alternative
when those properties differ. This clipboard is app-local, not a system Aseprite
clipboard, and represents one contiguous tag at a time.
Open documents plus copied sections share a conservative 64 MiB estimated data
budget; operations exceeding it are refused without replacing work. History is
bounded per document (the most recent undo is retained even when large). This is
not a hard process-memory limit. Recovery restores unsaved copies, not original
save paths; closing the app keeps drafts for every open drawing. Edits coalesce after about
half a second (at most two seconds of continuous edits); background/exit events
request an immediate flush. A force-kill before a write finishes can still lose
those newest edits. Keep important artwork in separately saved files too.
Drafts are never expired automatically: a 64-draft / 256 MiB peak-storage limit
refuses new writes visibly instead of evicting user work. Save or explicitly
discard older drafts to free space. Uninstalling/clearing app data removes them;
browser private mode, site-data clearing, storage eviction, or a changed site
origin can also remove browser drafts. Browser downloads retain the internal
copy because the app cannot confirm the download was kept. Only one app process
or browser tab may write a draft store at a time; another receives a storage
warning rather than being allowed to overwrite the first one's drafts.

Open **Palette → Preset palettes** for an offline, searchable library with color
previews: retro/system palettes, Monokai (Pygments), all Catppuccin flavors,
TIC-80/Sweetie16, DawnBringer16, and original game-art/material/character/food
ramps. Translucent swatches show checkerboards and exact opacity labels. Selecting a preset
replaces the document's palette across all frames; it never removes the bundled
presets or changes other open documents. RGBA/grayscale pixels stay unchanged.
Indexed sprites require confirmation before mapping every frame to the closest
preset colors, with a separate transparent slot. Linked cels are materialized when
needed for per-frame colors; the entire operation is one undo step. Palette
options → Undo restores the previous custom palette and artwork. Credits are
shown in the browser; license notices are available through its info button.
See [palette sources and licensing](docs/PALETTE_SOURCES.md). This is a curated
redistributable selection, not a claim to include every Aseprite/LibreSprite asset.
AAP-64 is not bundled; Gaem-64 is an independently authored alternative.
Its [GIMP palette file](art/palettes/Gaem-64.gpl) can be loaded in Aseprite;
the 64 RGB values and labels match the built-in preset exactly.

Use **Save as preset** to keep the current ordered ARGB swatches and names in
**My palettes** across documents and restarts. Personal presets can be edited,
renamed or deleted from their menu; built-ins offer **Save a copy** instead.
Editing a preset is staged until Save and never changes artwork until you apply
it. Saving a same-name palette creates a unique name rather than overwriting.
The library is local app data (no network); uninstalling/clearing app data removes
it, so keep important palettes in backed-up documents too.

Palette management supports exact-index swatch selection (including identical-color
entries), names, add/edit/reorder and removal with an explicit replacement. A color
edit affects the current frame. Structural edits remap all frame indices and names;
they refuse unequal palette sizes across the timeline. The transparent index cannot
be removed or used as a replacement. All edits are undoable.

Convert to indexed mode using each frame's palette, with an added transparency slot;
colors/alpha may be quantized and a full palette without a free slot is refused.
Conversion back to RGBA resolves per-frame palettes and linked cels to preserve
appearance. Keep original game assets when experimenting with conversion.

## Compatibility and safety

RGBA, indexed and grayscale/alpha Aseprite projects, compressed/linked cels,
frame palettes, layers, tags and user data are supported within explicit limits.
See [FORMAT.md](FORMAT.md) and [independent interoperability review](INTEROP_REVIEW.md).
Not every Aseprite feature is implemented: unsupported rendering semantics such as
blend modes, tilemaps and groups are rejected before editing. This is not desktop
Aseprite feature parity. Keep an original copy of important game assets.

The Flutter interface and touch canvas are shared. Android retains the existing
Kotlin codec/model behind a small platform channel, avoiding an unnecessary format
migration. Linux uses a Dart port with the same state/action contract. Both are
covered by fixture and regression tests; the independent parser check deliberately
reports only fields that parser actually understands.

Android package ID **org.pocketpixel** remains unchanged for update compatibility.
The display name and original Papirus-guideline icon are now SpriteDawg. Existing
permanent signing-key environment variable names are retained. Debug builds install side-by-side as **org.pocketpixel.debug**, so trying a development APK does not replace your existing app. They do not
have the release certificate: export files before replacing a differently signed
installation. Never uninstall your existing app just to try an unsigned update.

## Build and test

Use Flutter **3.47.8** (Dart 3.13), JDK 17, Android SDK 36/build-tools 36.0.0.
On Linux install clang, cmake, ninja-build, pkg-config, libgtk-3-dev and a C++ SDK.
For ARM64 Linux, bootstrap the official pinned SDK tag instead of the x64-only
stable archive: `git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git`,
then add its `bin` directory to PATH. CI uses this path on a native ARM64 runner.

```sh
flutter pub get
python3 scripts/fetch-fixtures.py
flutter analyze
flutter test
flutter build apk --debug
(cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug)
flutter build linux --release
scripts/package-linux.sh x64 0.3.65 # pass your build version; arm64 on ARM64
```

The fixture script verifies immutable upstream Git blob hashes. Test sprites retain
upstream copyright, are ignored by Git, and are never packaged in the application.

Debug builds include Flutter's development VM-service Internet permission for
emulator/device testing; release builds do not request Internet permission. The
Android editor contains no networking or analytics. Linux only contacts GitHub when you choose **Check for updates…**.

Independent reader regression (Node.js, no runtime app dependency):

```sh
git clone https://github.com/TheCyberRonin/ase-parser.git /tmp/ase-parser
git -C /tmp/ase-parser checkout 550bde9ec5d3dc03571d7ea5acd9612a49c61a80
# See scripts/check-ase-parser.cjs and tool/aseprite_interop.dart for invocation.
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Linux builds now produce only
`build/spritedawg-linux-x64.AppImage` or `build/spritedawg-linux-arm64.AppImage`,
plus their checksum files. Download the matching architecture, verify SHA256SUMS,
make it executable, then launch it:

```sh
chmod +x spritedawg-vX.Y.Z-linux-x64.AppImage
./spritedawg-vX.Y.Z-linux-x64.AppImage
```

GTK3, Flutter, plugins and native codecs are bundled. A compatible host glibc
(Ubuntu 24.04 or newer baseline), graphics drivers and display server are still
required. If the host lacks usable FUSE, run the same file with
`--appimage-extract-and-run`; no root installation is required. For inspection or
manual troubleshooting, `--appimage-extract` creates `squashfs-root`, whose
`./squashfs-root/AppRun` launches the extracted app. In-place updates require
launching the AppImage, including extraction-and-run, not an extracted AppDir.

Both x64 and ARM64 are built and launch-smoked on native CI runners. This does
**not** prove hardware/Wayland/touch compatibility on every Linux phone; no
physical ARM device is claimed tested without explicit verification results.
See [AppImage packaging and verification](docs/LINUX_APPIMAGE.md).

## CI and signing

CI runs Dart analysis/widget/codec tests, Android native codec tests/lint/APK build,
and separate Linux x64 + ARM64 release builds. Branches produce workflow artifacts.
Trusted main-branch pushes/merges automatically publish releases
only after all required checks pass and production Android signing succeeds.
Release assets include architecture-specific
Android APKs, Linux x64/ARM64 AppImages, and basename-relative SHA256 checksums.
Download the Android ARM64 APK for a Pixel 8; use the Linux ARM64 AppImage only for
a compatible glibc Linux system, not Android.

The old v0.1.1 release was debug-signed despite using `org.pocketpixel`. A release
signed by a different permanent key cannot update that installation in place.
Export your projects first; do not uninstall the old app until your files are safe.
The separately delivered **SpriteDawg Test** APK uses `org.pocketpixel.debug` and
is not the production release or an automatic-update channel.

Authorized release builds may use the existing permanent key via `POCKET_KEYSTORE`,
`POCKET_STORE_PASSWORD`, `POCKET_KEY_ALIAS`, `POCKET_KEY_PASSWORD`. Release builds
are not silently debug-signed, and no new permanent credential is generated.
The old native UI remains in `app/` as migration/reference source, but the default
build is the Flutter app in `android/`; its obsolete Compose UI is not packaged.

## Automatic releases

Merges/pushes to `main` publish only after Flutter tests/analyzer, independent codec checks, Android unit/lint/emulator checks, Linux x64/ARM64 builds, and production signing pass. PRs, feature branches, manual workflow dispatches and tag pushes do not publish. Existing permanent signing secrets are required; no development-key fallback is permitted. The public v0.2.0 signer fingerprint is pinned to protect update compatibility.

The workflow retains its existing identity and allocates version `MAJOR.MINOR.RUN_NUMBER` from the pubspec series (`0.3`), with Android base build number `10000 + RUN_NUMBER` plus Flutter's ABI offset. Run attempts reuse identifiers; new runs advance monotonically beyond v0.2.0. Do not recreate/rename the workflow or lower the release series without an explicit migration. CI passes these identifiers to Android and Linux builds without committing version bumps.

Publication stages a draft, checks all five platform assets against `SHA256SUMS`, then publishes. Interrupted drafts resume missing uploads without replacing existing bytes; conflicting bytes or a tag pointing elsewhere stop publication. Published retries verify the existing immutable release. Distinct runs use distinct tags; Publication explicitly reconciles the latest pointer to the highest published semantic version, rechecking after updates so an older finishing run cannot permanently downgrade it. No release asset is clobbered. Re-run failed jobs to resume the same build artifacts; a full rebuild that changes a partial draft's bytes intentionally fails rather than silently replacing them.

### Open with SpriteDawg

Android registers narrow Aseprite MIME/extension handlers; Linux bundles include MIME registration and a per-user installer. External opens add document tabs instead of replacing unsaved work. See [file association installation and provider limitations](FILE_ASSOCIATIONS.md).


### Canvas view modes

The overflow menu's **View · Tiled (3×3)** repeats the current frame seamlessly
in eight read-only neighbors. **View · Slide** shows the previous and next frame
beside the active frame instead of onion-skin overlays. Normal is the default;
these modes do not change exports or document data. Only the outlined central
canvas is editable; dragging a neighbor pans. Frame ends stay blank (no wrap).
Fit includes the context cells. Slide lazily caches one additional full-resolution
next-frame image, discards stale responses, and releases it when disabled.

### Linux installer and updates

Download `install-spritedawg.sh` from the [latest release](https://github.com/isaiahpettingill/SpriteDawg/releases/latest), review it, then run:

```sh
bash ~/Downloads/install-spritedawg.sh
```

The optional installer requires Python 3.9+, Linux x64 or ARM64, and no sudo.
It verifies the latest stable AppImage against SHA256SUMS and its native ELF/type
header, then installs one file at
`${XDG_DATA_HOME:-$HOME/.local/share}/spritedawg/SpriteDawg.AppImage`.
It registers the original icon and Aseprite associations without changing your
default editor. `shared-mime-info` and `desktop-file-utils` allow immediate cache
refresh; otherwise log out/in. Checksums detect corruption, not an independent
release signature. Verify the installer itself with the release's SHA256SUMS too.

**Existing tar installations:** run the new installer once to switch your launcher
to the AppImage. The old bundled updater only understands tar releases and cannot
perform that first transition. Old folders and `current` links are left untouched;
no documents, preferences, palettes or internal drafts are moved or deleted.

**Check for updates… → Install update** now replaces the **running AppImage file
itself**, at the same path. It checks the exact release, checksum and architecture,
stages on the same filesystem, then atomically renames the verified replacement.
A running process keeps its old inode/mount until you close it. There are no new
version folders. Failures before replacement retain the old app; activation errors
restore it. Read-only, symlink or unowned locations are refused with instructions
to save a new copy in a user-owned folder—never a sudo fallback.

Updates never close the editor or restart automatically. **Save your work, then
close and reopen the same AppImage** when ready. App-support paths and the stable
application ID are unchanged. The installer also supports `--check` and
`--version vX.Y.Z`; older versions cannot replace a newer recorded installation.

## Image and spritesheet export

Choose **⋮ → Export…**. GIF, APNG and WebP can export the current frame, all
frames, or a tag; tag direction and frame timing are retained within format
limits. PNG/QOI/AVIF export the current frame. GIF warns before reducing colors,
transparency or timing. AVIF is high-quality lossy (including alpha) and requires
at least 16×16 pixels; use PNG/APNG, lossless WebP or QOI for pixel-exact artwork.

**Spritesheet + JSON** writes untrimmed PNG cells with Aseprite-style JSON-array
frame rectangles, durations and tags. Choose columns and padding; the picker
creates a new folder containing both matching files, never overwriting an old
pair. Cancel leaves the project untouched. Exports are bounded to 32 MiB of
selected frame pixels; split large animations into tags if needed.
See [codec details and verification](docs/IMAGE_EXPORT_CODECS.md).

**Default user data** in the main menu saves a raw text template for new sprites
(including fresh startup/last-tab canvases). Text such as `credits="..."`,
`license="..."` or an explicitly chosen `title="..."` is kept verbatim. It does
not rename the document or change imported/recovered sprites. Use **User data →
Apply defaults to project** to apply it to an existing sprite; replacing text
requires confirmation and can be undone. Other user-data fields are preserved.

### Browser edition

The GitHub Pages build runs the editor locally in your browser. **Open** reads a
selected `.aseprite` file; it does not upload artwork. **Save** downloads a copy
rather than overwriting the original. Keep the download before closing the tab:
open documents are held in memory, and the unsaved indicator remains because the
browser cannot confirm that you kept the file. Personal palette presets persist
in this browser's site storage; clearing site data removes them.

PNG, GIF, APNG, lossless WebP and QOI exports are supported. Spritesheet PNG + JSON
download together as a ZIP. AVIF and the Linux updater require the installed app.
Large encodes can briefly block the browser UI; native builds retain background
workers. No accounts, analytics or artwork upload endpoints are used. Pages hosts
the app assets only; all editor processing stays in the browser.

The `SpriteDawg Web` workflow validates real Chrome drawing/import/export flows,
builds self-hosted Flutter assets under `/SpriteDawg/`, and publishes only trusted
main-branch builds. Repository **Settings → Pages → Source: GitHub Actions** must
be enabled by a repository administrator before the first deployment.
