#!/usr/bin/env bash
set -euo pipefail
image=$1 mode=$2 log=$3
if [[ "$mode" == extraction ]]; then
  "$image" --appimage-extract-and-run > "$log" 2>&1 &
else
  "$image" > "$log" 2>&1 &
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
xprop -id "$window" WM_CLASS _NET_WM_ICON >> "$log"
grep -q 'org.pocketpixel.SpriteDawg' "$log"
grep -q '_NET_WM_ICON(CARDINAL)' "$log"
# A second launch must route to the existing application rather than crash it.
if [[ "$mode" == extraction ]]; then
  timeout 30 "$image" --appimage-extract-and-run >> "$log" 2>&1
else
  timeout 30 "$image" >> "$log" 2>&1
fi
kill -0 "$pid"
