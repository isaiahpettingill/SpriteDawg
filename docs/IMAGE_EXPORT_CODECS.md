# Image export codec choices

All exports consume detached full-canvas, straight-alpha RGBA8 snapshots. Encoding
never mutates a document. GIF/APNG/WebP run off the Flutter UI isolate; native AVIF
uses its own worker. The app snapshot limit is 32 MiB; the standalone encoder defensively rejects
more than 64 MiB across selected playback frames;
codec temporary storage is additional. Still formats reject multiple frames.

## Dependencies

- `image: 4.12.0` (MIT, Dart >=3.0). Pure Dart GIF, APNG and lossless animated WebP
  encoders. WebP encoding is a real encoder in this version, not a decoder wrapper.
  https://pub.dev/packages/image/versions/4.12.0
  https://pub.dev/documentation/image/4.12.0/image/encodeWebP.html
- `flutter_avif_android: 3.1.0` and
  `flutter_avif_platform_interface: 3.1.0` (MIT, Dart >=3.4, Flutter >=3.22).
  Android includes JNI libraries with 16 KiB alignment for arm64. Linux uses
  local `packages/spritedawg_avif_linux`, compiling a pinned upstream Rust bridge
  for each native architecture; its Cargo.lock and build instructions are checked
  in. No FFmpeg process, network upload or runtime codec download is used.
  https://pub.dev/packages/flutter_avif_android/versions/3.1.0
  https://pub.dev/packages/flutter_avif_platform_interface/versions/3.1.0

The direct AVIF interface accepts straight RGBA and avoids the convenience
`encodeAvif(PNG)` wrapper's premultiplied `dart:ui rawRgba` intermediate. Color and
alpha quantizers are set to zero (highest quality), but rav1e still alters RGB
and alpha, including turning alpha 0 into 1 in the independent fixture. AVIF
is explicitly lossy, including transparency, not pixel-exact. It requires both
canvas dimensions to be at least 16 pixels; smaller artwork is rejected before
the native call, which otherwise panics and leaves a pending future. The app
uses a 60-second timeout as a final guard. APNG, lossless WebP and QOI are the choices
for exact colors. AVIF export is intentionally still-only.

GIF uses up to 256 opaque colors (255 when transparency is present), no dithering,
10 ms timing (rounded), and an alpha threshold
of 128. APNG/WebP preserve alpha and millisecond durations. GIF's palette
quantization can change colors only when the palette capacity is exceeded.
Loop counts mean total plays in all formats; zero means forever, and GIF is
normalized to its different repeat-extension semantics. WebP retains hidden RGB under transparent pixels.

QOI uses the MIT-licensed encoder from **imcodec 0.5.5**, vendored at
`lib/export/vendor/imcodec_qoi_encoder.dart` rather than requiring that package's
Dart 3.13 SDK baseline. The RUN/INDEX/DIFF/LUMA/RGB/RGBA algorithm is retained;
adaptations replace its Image/RasterEncoder interfaces with straight-RGBA bytes
and dimensions, and its OutputBuffer with a single bounded allocation. Full
copyright/license text is in `LICENSES/imcodec-MIT.txt` and the bundled notices.
An independent specification reader and Pillow validate the result.

Source: https://pub.dev/packages/imcodec/versions/0.5.5
Archive: https://pub.dev/api/archives/imcodec-0.5.5.tar.gz
Archive SHA-256: `a9003dfe426d56406a39b5974b3f50b620733fbb9544e62ee80bdb74773ae47d`
Upstream file: `lib/src/codecs/qoi/encoder.dart`.

The application must retain Flutter dependency license notices. Native AVIF
upstream's additional third-party acknowledgements also apply:
https://github.com/yekeskin/flutter_avif/blob/main/ACKNOWLEDGEMENTS.md

## Native packaging verification

The upstream 3.1.0 Linux binary is **x86-64 only**. Do not enable that plugin
unmodified for Linux ARM64: its automatic Dart registration loads the binary
at startup. Native ARM64 must build the Rust bridge and libavif dependencies
for that architecture. The Android arm64 binary has 16 KiB ELF LOAD alignment.
These observations are not a substitute for release-build integration tests.

## Verification evidence

The pure Dart harness passes 10 tests, including GIF palette/transparent-color
limits and total-play loop semantics. Independent Pillow 12.3.0 decoded three
GIF/APNG/WebP frames with 70/110/130 ms durations, two total plays, and correct
transparent clearing; QOI pixels match exactly. The upstream Linux x86-64
3.1.0 binary also encoded the 18x16 AVIF fixture, with maximum RGBA errors
[2,1,4,1]. Linux ARM64 source-build results are established separately in CI.

The vendored QOI adapter uses an unsigned 32-bit index table so packed RGBA
comparison remains exact for red values ≥128; this avoids unnecessary fallback
opcodes without changing the stream format. Android builds align the upstream
plugin Java target with AGP 9 Kotlin/JDK 17 rather than disabling validation.


### Android registrar compatibility

Pinned flutter_avif_android 3.1.0 ships equivalent Java and Kotlin
`FlutterAvifPlugin` registrars (same channel, getPlatformVersion handler and
detach behavior). AGP 9 automatically compiles both, causing a redeclaration.
Only this dependency's redundant Kotlin compilation is disabled; a source-count
and exact-path guard fails if new Kotlin logic appears. The original Java
registrar and all JNI binaries remain compiled/packaged. App Kotlin, lint,
unit tests and the device AVIF encode/decode test are not disabled. The plugin
compile SDK is aligned to the app's 36 for current Flutter AndroidX metadata;
this does not raise the app's minimum supported Android version.
