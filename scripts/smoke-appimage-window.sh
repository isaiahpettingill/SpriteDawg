#!/usr/bin/env bash
set -euo pipefail
image=$1 mode=$2 log=$3 expected_icon=$4 version=$5
: > "$log"
if [[ "$mode" == extraction ]]; then
  "$image" --appimage-extract-and-run >> "$log" 2>&1 &
else
  "$image" >> "$log" 2>&1 &
fi
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
window=''
for attempt in $(seq 1 90); do
  if ! kill -0 "$pid" 2>/dev/null; then cat "$log"; exit 1; fi
  window=$(xdotool search --onlyvisible --class 'org.pocketpixel.SpriteDawg' 2>/dev/null | head -n1 || true)
  [[ -z "$window" ]] || break
  sleep 1
done
if [[ -z "$window" ]]; then cat "$log"; echo 'Packaged Flutter app never rendered a window.' >&2; exit 1; fi
xprop -id "$window" WM_CLASS >> "$log"
grep -q 'org.pocketpixel.SpriteDawg' "$log"
# xprop's built-in icon pretty-printer omits large icons; inspect raw CARDINALs.
xprop -id "$window" -f _NET_WM_ICON 32c ' = $0+\n' _NET_WM_ICON > "$log.icon"
python3 scripts/check-window-icon.py verify "$log.icon" "$expected_icon" >> "$log"
rm "$log.icon"
assert_original_window() {
  kill -0 "$pid"
  local visible
  visible=$(xdotool search --onlyvisible --class 'org.pocketpixel.SpriteDawg')
  [[ "$visible" == "$window" ]] || { echo 'Original editor window disappeared or a duplicate appeared.' >&2; exit 1; }
}
# Exercise production checksum/atomic replacement while this real GUI is alive.
python3 scripts/smoke-appimage-update.py "$image" "$version" >> "$log"
assert_original_window
# A second launch must route to the existing application rather than crash it.
if [[ "$mode" == extraction ]]; then
  timeout 30 "$image" --appimage-extract-and-run >> "$log" 2>&1
else
  timeout 30 "$image" >> "$log" 2>&1
fi
assert_original_window
echo 'Original rendered editor remains visible after replacement and repeated launch.' >> "$log"
