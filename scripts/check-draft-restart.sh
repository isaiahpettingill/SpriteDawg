#!/usr/bin/env bash
# Disposable emulator only. Keep package data between two integration entrypoints.
# Flutter 3.47.8 normally updates Android APKs with adb install -r. Its integration
# teardown uninstalls by default, so BOTH phases require --no-uninstall. If an
# installation fallback does wipe data, verification MUST fail, never reseed it.
set -euo pipefail

serial="${1:-emulator-5554}"
package=org.pocketpixel.debug
adb -s "$serial" wait-for-device

flutter test integration_test/draft_restart_seed_test.dart \
  -d "$serial" --no-uninstall --reporter expanded

# Inspect only this disposable debug app's committed native snapshots. Missing
# files (including an accidental uninstall) are a hard failure before relaunch.
draft_checksums() {
  adb -s "$serial" shell \
    "run-as $package sh -c 'cd files && sha256sum draft-*.sdd'" \
    | tr -d '\r' | LC_ALL=C sort
}
before="$(draft_checksums)"
if [[ "$(printf '%s\n' "$before" | wc -l)" -ne 2 ]]; then
  echo 'Expected exactly two committed seed drafts; refusing an invalid restart test.' >&2
  exit 1
fi
printf 'Committed draft checksums before force-stop:\n%s\n' "$before"
adb -s "$serial" shell am force-stop "$package"
if adb -s "$serial" shell pidof "$package" | grep -Eq '[0-9]'; then
  echo 'The seed application process is still running.' >&2
  exit 1
fi
after="$(draft_checksums)"
if [[ "$before" != "$after" ]]; then
  echo 'Draft bytes changed or disappeared during force-stop.' >&2
  exit 1
fi

# This entrypoint requires the seed manifest, different process ID, exact draft
# IDs/names, metadata, dimensions, and full pixel buffers. It never creates data.
# Only those proven fixture IDs are discarded after every assertion passes.
flutter test integration_test/draft_restart_verify_test.dart \
  -d "$serial" --no-uninstall --reporter expanded
