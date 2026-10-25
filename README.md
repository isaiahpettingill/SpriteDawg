# SpriteDawg

<img src="art/spritedawg.svg" width="96" alt="SpriteDawg pixel dog icon">

An offline, touch-first **Flutter** pixel-art editor for Android and Linux phones.
The goal is simple: open a sprite, draw comfortably on the go, and keep your work.
MIT licensed, no ads, accounts, tracking, networking or broad Android storage permission.

## Draw

- Pencil, eraser, flood fill, eyedropper, line, rectangle, ellipse and pan.
- One finger/stylus draws; two fingers pan/pinch. Adding a second finger **cancels**
  the pending stroke, and drawing cannot resume until all fingers lift.
- Brush size, palette, custom RGBA color, grid, previous-frame onion skin and Fit.
- Undo/redo; visible/editable layer safeguards; layers, opacity and ordering.
- Frames, duration, duplication and animation playback with direction/repeat tags.
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

```sh
flutter pub get
python3 scripts/fetch-fixtures.py
flutter analyze
flutter test
flutter build apk --debug
(cd android && ./gradlew testDebugUnitTest lintDebug)
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
and separate Linux x64 + ARM64 release builds. Outputs are **workflow artifacts**,
not automatic public releases. This rewrite does not merge or publish a release.

Authorized release builds may use the existing permanent key via `POCKET_KEYSTORE`,
`POCKET_STORE_PASSWORD`, `POCKET_KEY_ALIAS`, `POCKET_KEY_PASSWORD`. Release builds
are not silently debug-signed, and no new permanent credential is generated.
The old native UI remains in `app/` as migration/reference source, but the default
build is the Flutter app in `android/`; its obsolete Compose UI is not packaged.
