# Fast CI and full checks

Fast Flutter tests/analyzer and release-tool regressions always run. All tests
remain in the repository; this change selects when expensive jobs run, not which
bugs are acceptable.

- Feature pushes no longer duplicate the open PR workflow. Main pushes still
  automatically build and publish releases.
- PRs changing only known documentation skip Android/emulator/Linux jobs. Unknown
  paths run all jobs. Pure UI changes skip the independent file-parser cross-check,
  but still run Flutter tests, native/brush parity and emulator interactions.
- A main merge can reuse expensive Android/emulator/parser validation only after
  verifying a merged, same-repository PR; the exact head SHA; this workflow's
  completed successful test, Android and device jobs; and a small `validated-tree`
  artifact recording the **actual checkout Git tree** tested by that PR run.
  The recorded tree and the PR head tree must both equal the current main tree.
  Synthetic merge differences, fork PRs, missing/expired artifacts, API failures,
  failed/skipped required jobs, direct pushes and uncertain metadata all run full
  checks instead. No PR binary is used for a production release.
- Linux release packages and signed Android APKs are always built from the current
  main commit. Certificate, package ID, version, offline-permission and checksum
  verification remain mandatory. Release guards accept only explicitly planned
  validation skips, never failures or cancellations.
- Run **Actions → SpriteDawg Flutter → Run workflow** for the full suite, including
  emulator and independent parser. It does not publish a release.
- Superseded PR runs are canceled, but a running main release is not canceled.
- Linux package installation checks existing packages first and bounds mirror
  timeouts/retries so a stalled mirror cannot wait for hours.

## Observed baseline, not a performance promise

Run [40354749852](https://github.com/isaiahpettingill/SpriteDawg/actions/runs/40354749852)
(2026-10-26): Flutter tests 35s, emulator 303s, debug APK build 238s,
native/lint 65s, signed build/verification 251s; Linux x64 APT took 754s.
Avoiding duplicate post-merge Android/emulator validation can remove roughly six
minutes before signing for identical tested trees. Actual time depends on caches,
runners and network. The first run without a validation record deliberately does
not reuse older results.
