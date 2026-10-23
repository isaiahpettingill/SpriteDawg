# Pocket Pixel

<img src="art/pocket-pixel-icon.png" width="96" alt="Pocket Pixel icon">

[Download the Android APK](https://github.com/isaiahpettingill/SpriteDawg/releases)

A small native Android pixel editor for Aseprite projects. Kotlin, Jetpack Compose,
Material 3, and a native Android Canvas view. Android 10+ (API 29); designed for
portrait phones, including Pixel 8 / GrapheneOS. MIT licensed.

No ads, payments, accounts, analytics, networking code, INTERNET permission, or
broad storage permission. All editing is offline. Build tools download dependencies;
the installed application does not connect to the internet.

## Build

Open this directory in Android Studio, install Android SDK Platform 35 and Build
Tools 35.0.0, and use JDK 17. The Gradle wrapper is included. For command-line builds,
set `ANDROID_HOME` or create `local.properties` with `sdk.dir=/absolute/sdk/path`.

`python3 scripts/fetch-fixtures.py`

`./gradlew testDebugUnitTest lintDebug assembleDebug`

With an emulator or device connected: `./gradlew connectedDebugAndroidTest`.

Windows Git Bash can use the same commands (`python` if that is your Python command).
APK: `app/build/outputs/apk/debug/app-debug.apk`. Install it with Android's package
installer or `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

The fixture fetch downloads original Aseprite test sprites by immutable Git blob
hash and verifies every hash. Those upstream assets are test-only, are not part of
the MIT application, and are never packaged in its APK. They originate at
https://github.com/aseprite/aseprite/tree/main/tests/sprites and retain upstream
copyright and terms. They are intentionally excluded from this source distribution;
the script reproduces the exact tested inputs. Local tests work offline after this
one-time fetch.

## Use

- **Open** uses Android's document picker for `.ase` and `.aseprite` files.
- **Save** writes back to the chosen URI; **More → Save As** chooses a new document.
  If a provider declines write permission, use Save As. Save validates encoded data
  before opening the output stream and keeps a recovery copy first. SAF providers
  do not universally offer atomic replacement; a provider failure can leave its
  output incomplete, but the local recovery copy remains available.
- One finger/stylus draws. Two fingers pan and pinch; adding a second finger cancels
  the in-progress stroke. **Pan** supports one-finger panning. **Fit** recenters.
- Pencil and eraser have sizes 1–16. Fill is four-connected. Line/rectangle tools
  preview until release. Color opens AARRGGBB hex and RGBA sliders. Checkerboard,
  nearest-neighbor rendering, optional grid, and previous-frame onion skin are built in.
- **Layers / Frames** expands the compact panel. Layers can be selected, renamed,
  reordered, hidden, added/deleted, or assigned opacity. The first stored layer is
  the bottom layer; the panel displays topmost first. Opening a file selects its
  topmost visible editable layer. The canvas header shows the active tool and layer.
  Hidden-layer drawing and indexed-background erasing explain why editing is blocked.
- Frames can be added, duplicated, deleted, selected, timed, and played. **Tags**
  selects a loaded tag for playback or creates forward tags. Loaded direction,
  repeat count, range, color, and user data survive saves. New tag ranges are
  entered with one-based frame numbers.
- **Data** or **More → User data** edits sprite, active-layer, active-cel, or tag
  text. JSON such as `{"strength":12,"health":40}` is stored verbatim. Existing user
  data colors and typed property payloads are preserved. Scalar typed properties
  can be added/edited (integers, decimals, text, booleans); existing numeric types
  are retained. Nested maps, vectors, geometry, and UUIDs stay read-only. Text is limited to the format's 65535 UTF-8 bytes.
- Resize anchors at the upper left and retains off-canvas pixels. Flips act on the
  active frame/layer cel. PNG export flattens the current frame into a new PNG;
  it does not flatten the Aseprite document.
- Undo/redo is bounded to 30 snapshots and approximately 48 MiB (one larger
  snapshot may be retained). Undo covers drawing, metadata, layers, and frames.
- Unsaved edits remain in memory with an app-private, atomic, debounced recovery
  file. A recovery prompt appears after process death. Recovery opens an unsaved
  copy so it cannot overwrite an old URI by mistake. Rotation retains the editor.
  The last ~450 ms before an unexpected kill may not have reached recovery.

## Compatibility

RGBA, native indexed, and grayscale/alpha projects are supported, including
layers, animation, linked/compressed cels, palettes, tags, and typed user data.
Unsupported rendering features are refused before editing. See [FORMAT.md](FORMAT.md)
for the exact preservation policy, safety limits, tests, and code layout.

## GitHub CI and releases

The included workflow tests, lints, builds, and uploads a debug APK for pushes and
pull requests. Instrumented tests exercise the actual touch controls on an Android
emulator. A `v*` tag (or a main-branch commit marked `[release]`) creates a GitHub
Release only after unit tests, lint, and interaction tests pass.

For tagged releases configure four repository secrets:
`POCKET_KEYSTORE_BASE64`, `POCKET_STORE_PASSWORD`, `POCKET_KEY_ALIAS`, and
`POCKET_KEY_PASSWORD`. Generate your own keystore with Android Studio's signing
wizard or `keytool`; back it up securely and reuse it for updates. Without a private release key, the workflow publishes an explicitly marked
development prerelease using a CI-generated debug key. Debug keys from different
build environments differ: uninstall the old app if Android rejects an update,
after saving your projects. Configure the signing secrets for stable signed updates.
Increase `versionCode` and `versionName` in `app/build.gradle.kts` before releases.
