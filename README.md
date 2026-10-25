# SpriteDawg

<img src="art/spritedawg.svg" width="96" alt="SpriteDawg pixel dog icon">

An offline, touch-first **Flutter** pixel-art editor for Android and Linux phones.
The goal is simple: open a sprite, draw comfortably on the go, and keep your work.
MIT licensed, no ads, accounts, tracking, networking or broad Android storage permission.

## Draw

- Pencil, eraser, flood fill, eyedropper, line, outlined/filled rectangles and
  ellipses, spray, blur, jumble and pan. The eraser has its own eraser icon.
- Two-color horizontal/vertical gradients stay inside the connected fill region.
  Spray has adjustable density; blur/jumble have strength controls. Random tools
  use a fixed seed per gesture, and the entire gesture is one undo step.
- Horizontal/vertical symmetry mirrors around the canvas center. Center-line
  pixels are not applied repeatedly. In indexed mode, gradients and blur map
  results to the current palette; jumble moves native pixel indices.
- One finger/stylus draws; two fingers pan/pinch. Adding a second finger **cancels**
  the pending stroke, and drawing cannot resume until all fingers lift.
- Brush size, palette, custom RGBA color, grid, previous-frame onion skin and Fit.
- Undo/redo; visible/editable layer safeguards; layers, opacity and ordering.
- Frames, duration, duplication and animation playback with direction/repeat tags.
- Visual tag editing keeps frame thumbnails visible with the selected range and
  current frame marked. Rename, adjust endpoints or duplicate quickly; browse tile
  variants without starting playback, or explicitly preview an animation. Tags
  remain generic, contiguous Aseprite ranges, not new incompatible tag types.
- Sprite/layer/cel/tag user-data text; existing binary typed-property payloads remain
  attached to their original objects. Unsupported advanced features are refused,
  rather than silently flattened.
- Aseprite open/save/save-as; PNG export only flattens the exported image.
- Atomic app-private recovery after edits. A failed recovery write is shown, not
  treated as success. Recovering opens an **unsaved copy**, never an old save path.

Android uses the system document picker. Linux uses native GTK file dialogs.
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
save paths; closing the app keeps recovery for every dirty tab.

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
scripts/package-linux.sh x64 # arm64 on an ARM64 Linux host
```

The fixture script verifies immutable upstream Git blob hashes. Test sprites retain
upstream copyright, are ignored by Git, and are never packaged in the application.

Debug builds include Flutter's development VM-service Internet permission for
emulator/device testing; release builds do not request Internet permission. The
editor itself contains no networking or analytics.

Independent reader regression (Node.js, no runtime app dependency):

```sh
git clone https://github.com/TheCyberRonin/ase-parser.git /tmp/ase-parser
git -C /tmp/ase-parser checkout 550bde9ec5d3dc03571d7ea5acd9612a49c61a80
# See scripts/check-ase-parser.cjs and tool/aseprite_interop.dart for invocation.
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Linux archive:
`build/spritedawg-linux-x64.tar.gz` (or `arm64`). Extract the entire archive, run
`./spritedawg`; optional `./install-desktop.sh` installs the per-user launcher/icon.
Do not move the extracted directory after installing its launcher.

Linux bundles require compatible glibc/GTK3 and a working graphics stack. ARM64
Linux builds are separate from x64 desktop builds; building either does **not**
prove hardware/Wayland/touch compatibility on every Linux phone. No real phone is
claimed tested unless explicitly recorded in the PR verification results.

## CI and signing

CI runs Dart analysis/widget/codec tests, Android native codec tests/lint/APK build,
and separate Linux x64 + ARM64 release builds. Branches produce workflow artifacts.
Explicit version tags or a main-branch merge marked `[release]` publish releases
only after all required checks pass and production Android signing succeeds.
Release assets include architecture-specific
Android APKs, Linux x64/ARM64 archives, and basename-relative SHA256 checksums.
Download the Android ARM64 APK for a Pixel 8; use the Linux ARM64 archive only for
a compatible glibc/GTK3 Linux system, not Android.

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
