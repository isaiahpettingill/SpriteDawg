#!/usr/bin/env bash
# Run against the installed debug APK on the integration emulator.
set -eu
serial=${1:-emulator-5554}
matches() {
    adb -s "$serial" shell cmd package query-activities --components \
        -a "android.intent.action.$1" -c android.intent.category.DEFAULT \
        -p org.pocketpixel.debug -d "$2" "${@:3}" | tr -d '\r' | grep -Fx 'org.pocketpixel.debug/org.pocketpixel.MainActivity'
}
for action in VIEW EDIT; do
    matches "$action" content://com.android.providers.downloads.documents/document/1936 -t application/octet-stream
    matches "$action" content://provider/document/73 -t image/x-aseprite
    matches "$action" content://provider/sprites/walk.v2.ASE -t text/plain
    matches "$action" file:///sdcard/Download/walk.v2.aseprite
    if matches "$action" content://provider/document/photo.jpg -t image/jpeg; then
        echo 'SpriteDawg matched an unrelated JPEG.' >&2
        exit 1
    fi
done
