# SpriteDawg native Linux AVIF bridge

This local Flutter plugin replaces `flutter_avif_linux` 3.1.0's x86-64-only
prebuilt. It compiles the same bridge ABI **on the target architecture** so
Linux x86-64 and ARM64 builds never load a mismatched binary. It is not a
cross-compilation recipe. Do not additionally depend on `flutter_avif_linux`
or the umbrella `flutter_avif` package.

## Reproducible build inputs

- Vendored `rust/src` and original `rust/Cargo.toml`:
  https://github.com/yekeskin/flutter_avif/tree/513c918e4f881a1c08600149a56ac2e604863f79/rust
- Both `libavif-rs` git dependencies now pin revision
  `519cb3ea526d3a7316face89f52bcbb2c432ec9e` instead of mutable default HEAD.
  https://github.com/yekeskin/libavif-rs/tree/519cb3ea526d3a7316face89f52bcbb2c432ec9e
- Cargo.lock generated with official Cargo **1.90.0**; CI should pin Rust 1.90.0.
  CMake runs `cargo build --release --locked` with a build-directory target path.
- Upstream bridge is MIT (`LICENSE` retained). libavif-rs is BSD-2-Clause;
  libavif/dav1d/rav1e and locked Rust crates retain their own licenses. The
  upstream notice file is retained as `UPSTREAM_ACKNOWLEDGEMENTS.md`.

Build dependencies: Rust/Cargo 1.90.0, C/C++ compiler, CMake, pkg-config, Meson,
Ninja, NASM, Flutter's usual GTK/Linux development dependencies. Cargo downloads
pinned source dependencies **at build time only**. Runtime encoding is offline.
Cargo's git dependency fetch recursively obtains pinned libavif/dav1d sources.
No system FFmpeg, AVIF command-line utility or system libavif is required.

## Integration verification

Build Flutter on native x86-64 and ARM64 CI runners. Then locate the built
`libflutter_avif.so` in the Linux bundle's `lib` directory and run:

```
dart run tool/image_export_interop.dart build/export-interop /absolute/path/to/bundle/lib/libflutter_avif.so
python scripts/check-image-exports.py build/export-interop --require-avif
```

The verifier uses Pillow 12.3.0, not the exporting codec, to inspect pixels,
transparency, frame count, timing and loops. A successful Cargo lock resolution
alone is **not** evidence that the native build or runtime interop passed.

Local safety changes in `rust/src/flutter_avif.rs`: encoding errors return an
empty byte vector rather than panic (so the Dart future completes with an app
error), and the libavif output buffer starts with a null pointer as required by
its allocation contract. Decode code is unchanged.

`THIRD_PARTY_NOTICES.txt` contains deduplicated full license texts and copyright
attributions for native codecs and locked dependencies. Crate archive bytes were
verified against Cargo.lock checksums. It is bundled as a Flutter package asset
and registered by the app on both Android and Linux. The protobuf runtime is
exactly 3.7.1 to match the five checked-in generated message modules.
