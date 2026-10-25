# Independent Aseprite review

Reviewed 2026-10-25. This is source comparison, **not proof of full Aseprite parity**.
External implementations were read through GitHub; none were installed or executed
by this reviewer. Runtime fixture interoperability should additionally run in CI.

## References actually inspected

- [Current official file specification](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md).
- [Aseprite normal blending](https://github.com/aseprite/aseprite/blob/main/src/doc/blend_funcs.cpp), blob `74b00720ab3d0207df109020228f0d90bb13834e`, function `rgba_blender_normal`.
- [Aseprite color scales](https://github.com/aseprite/aseprite/blob/main/src/doc/color_scales.h), blob `0fdaf92d38ac1d55f2e7bd5cb91f8451d147f9b1`.
- [LibreSprite decoder](https://github.com/LibreSprite/LibreSprite/blob/master/src/app/file/ase_format.cpp), blob `2af20d5a407e01b9c6c026c2451c3d0417f5fe79`, and [color scales](https://github.com/LibreSprite/LibreSprite/blob/master/src/doc/color_scales.h), blob `5ed8be8f1c774b550b27523979e1b1d908955c4b`.
- Independent Rust [asefile pixel decoding](https://github.com/alpine-alpaca/asefile/blob/main/src/pixel.rs), blob `f5baee1fb844462785b657c73365b24cc2e6a95f`; [cel decoding](https://github.com/alpine-alpaca/asefile/blob/main/src/cel.rs), blob `5576f720aaf2417040f51277909363c481168525`; [palette](https://github.com/alpine-alpaca/asefile/blob/main/src/palette.rs), blob `09116faf10f84ee996ee93f1250cac92f56127f6`; [blending](https://github.com/alpine-alpaca/asefile/blob/main/src/blend.rs), blob `50516244d2921393563b7c19b9909f6c32265a07`; and `src/parse.rs`, `src/tags.rs`.

## Concrete findings sent to both backend owners

1. **Palette corruption after frame deletion.** A three-frame indexed document
   sets index 1 red in frame 2 and index 2 blue in frame 3. Deleting frame 2,
   writing, and reading changed frame 3's inherited index 1 to black. Reproduced
   with the actual Dart codec, not inferred solely from source. The writer reused
   a partial palette chunk without restoring the effective inherited palette.
   Regression must cover both backends and preserve palette entry names.
2. **Legacy six-bit colors.** Decoder arithmetic originally differed from all
   three reference implementations for inputs 11–15 and 48–52. Example: input 11
   became 45 rather than 44. Use reference bit replication and test all 64 values.
3. **Normal blend rounding.** The Rust reference's existing test and current
   Aseprite implementation agree: backdrop RGBA `(0,205,249,255)`, foreground
   `(237,118,20,255)`, opacity 128 produce `(118,162,135,255)`. Original SpriteDawg
   arithmetic produced `(119,161,134,255)`. This affects preview/PNG, not stored
   individual cel pixels. Comparison calculated from inspected formulas; an
   external renderer was not executed.

Fix status and executable regression results belong to the implementation/CI
report; these findings describe the code at review time, not necessarily HEAD.

Follow-up: the Dart owner fixed all three and reported 32 direct-Dart harness
tests passing. This reviewer independently reran the original palette-deletion
reproducer after the fix: before and after were both
`(0, ffff0000, ff0000ff)`. Source inspection also confirms the corrected six-bit
expansion and official normal-blend integer algorithm. The backend owner reports
11 external assets cross-checked with independent Node `ase-parser` at commit
`550bde9ec5d3dc03571d7ea5acd9612a49c61a80`: dimensions, color depth, frame count,
layers, tags, timing, and raw cel pixels/positions/opacity/links matched. That
comparison did **not** validate palette or user-data equivalence.

## Coverage matrix

| Area | Source comparison / supported boundary | Runtime evidence from this reviewer |
|---|---|---|
| RGBA / grayscale / indexed | Channel order and indexed background transparency agree with asefile `pixel.rs` and official spec | No external fixture run |
| Raw / zlib cels | Encodings and signed placement match reference structure | No external decoder run |
| Linked cels | Own cel placement/opacity retained; links detached before structural edits. SpriteDawg refuses forward links; asefile permits references to raw cels | Source only |
| Palettes | Effective palette per frame; raw named-entry chunks retained. Structural-edit defect above found | Dart corruption repro executed |
| Layers | Normal image layers only; rejects groups, tilemaps, reference layers and non-normal blend modes rather than flattening | Source only |
| Timing / tags | Frame duration with legacy speed fallback; tag ranges, repeat and directions 0–3 retained | Source only; UI playback not launched |
| User data | Text/color plus opaque typed-property bytes; per-object/tag attachment and project data after palette | Source only; no typed-property external fixture |
| Unknown chunks / advanced features | Refused, not silently dropped; slices, external-file references, ICC/custom profiles and cel extras not general-purpose supported | Source only |
| Normal compositing | Reference rounding discrepancy above | Formula comparison only |

The official specification is authoritative where an independent parser lags:
the inspected asefile implementation only recognizes tag directions 0–2 and
uses one final palette during validation. It is therefore not a sufficient oracle
for ping-pong-reverse or animated partial palettes. Aseprite/LibreSprite fixtures
and narrowly targeted byte-level assertions are needed for those cases.

## Mobile regression tests

`test/review_mobile_test.dart` adds 320px layout, pinch coordinate/pointer-count,
tool-change cancellation, and confirmed dirty-back/recovery-discard tests.
Bootstrap was initially stopped after an execution security denial; the lead
later established and approved a safe CI-mode environment. The UI owner's test
run found real bottom-toolbar overflow at 320/390px and Tags-header overflow at
320px. Both were fixed. A later dependency-resolution permission denial was
resolved by the lead using current task authorization and telemetry suppression.
The lead supplied the exact final validation result: execution session `26311`,
exit 0, `flutter analyze && flutter test --reporter expanded`, ending with
`No issues found! (ran in 15.1s)` and `00:03 +60: All tests passed!`.
This full run included the 320px panel, pinch, tool-cancellation and confirmed
Back/discard-recovery tests, plus editor, engine, desktop and capture tests.
No log file was redirected; this result is attributed to the lead's completed
tool execution, not an additional independent rerun by this reviewer.
Native Kotlin parity regressions were added for all three codec findings, but
their execution was still unverified when the native owner reported status.
No real Android process-death
recovery or physical Linux-phone interaction has been verified by this reviewer.

## Final implementation verification (2026-10-25)

The portable-engine owner subsequently ran the **actual Flutter test runner**:

```sh
flutter test test/desktop_backend_test.dart test/engine_test.dart
```

Result: **46 tests passed** (36 codec/model/engine tests and 10 desktop filesystem
adapter tests). This supersedes the earlier standalone-harness counts above for
these files; it does not turn the reviewer's source-only observations into device
tests. Targeted `dart analyze` of the engine, desktop adapter, these tests, and the
interop exporter also completed with **no issues**.

Engine coverage includes every-byte truncation, malformed/unsupported structures,
48 stored/fixed/dynamic DEFLATE samples and rejection of trailing compressed bytes,
native RGB/indexed/grayscale round trips, linked cels, all drawing tools,
undo/redo atomicity, palette names/inheritance after frame deletion, all 64 legacy
six-bit values, official normal-blend rounding cases, and actual typed-property
payloads extracted from immutable upstream fixtures. Desktop coverage includes
picker cancellation, invalid open, atomic save, write failure retaining recovery,
recovery failure warnings, restored unsaved copies, failed cleanup returning fresh
state, and serialized overlapping commands. These use temporary directories and
injected pickers, not real desktop dialogs or phones.

After the final zlib validation changes, these commands were executed again:

```sh
dart tool/aseprite_interop.dart
node scripts/check-ase-parser.cjs /tmp/spritedawg-ase-parser/Aseprite.js
```

The external MIT-licensed [ase-parser](https://github.com/TheCyberRonin/ase-parser)
checkout was pinned to `550bde9ec5d3dc03571d7ea5acd9612a49c61a80`.
**All 11 supported immutable upstream fixtures passed** independent comparisons
between the original files and SpriteDawg's newly encoded files: dimensions,
color depth, frame count, layer records, tag records, durations, and raw decoded
cel pixels/positions/opacity/links. The checker does **not** compare palettes,
user data, rendered frame compositing, or visual application behavior. Palette
and metadata preservation have dedicated local regressions, but those must not
be described as independent-parser validation.

The exporter also regenerated per-frame RGBA files under
`/tmp/spritedawg-dart-interop` for a separate native-backend cross-check. Generation
alone is not evidence that the native comparison ran or passed. No third-party
parser code or copyrighted upstream fixture bytes are bundled in the application.

## Alpha/rendering follow-up

A focused Flutter regression proved that sending straight RGBA bytes directly to
`rgba8888` brightened translucent channels (`200,100,50,128` became
`255,199,100,128`). Display/onion images now use the documented straight-alpha
float format when needed, with exact low-alpha regressions. Android and Linux PNG
exports bypass premultiplied render surfaces and write standard 8-bit RGBA PNGs
without quantizing source channels. Independent JDK ImageIO, PNG CRC/decompression,
and Flutter decoding checks validate these exports. The complete local Flutter
suite passes 67 tests with a clean analyzer; the complete native standalone JVM
suite passes 45 tests, including 11-file/41-frame Dart/Kotlin comparisons. These
are not claims of physical-device testing. Final Android/ARM64 CI is tracked on
the draft PR.
