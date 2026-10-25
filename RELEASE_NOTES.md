# SpriteDawg 0.2.0

SpriteDawg is now a Flutter pixel-art editor for Android and Linux, focused on drawing on the go. Free, open source, offline: no accounts, ads, analytics, or Android internet permission.

## Drawing and animation

- Touch-first pencil, eraser, fill, eyedropper, line, rectangle, and ellipse tools.
- Two-finger pan/zoom cancels the pending stroke instead of leaving stray marks; one-finger Pan and Fit are also available.
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
