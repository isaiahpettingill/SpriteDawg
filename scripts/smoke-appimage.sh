#!/usr/bin/env bash
# Real packaged GUI checks run natively for both architectures, without user data.
set -euo pipefail
image=$(realpath "${1:?AppImage path}")
arch=${2:?architecture}
version=${3:?version without v}
root=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 scripts/check-appimage.py "$image" "$arch"
(cd "$(dirname "$image")" && sha256sum --check "$(basename "$image").sha256")
mkdir -p "$work/extracted" "$work/portable with spaces"
cp "$image" "$work/portable with spaces/SpriteDawg.AppImage"
chmod 755 "$work/portable with spaces/SpriteDawg.AppImage"
(cd "$work/extracted" && "$image" --appimage-extract > "$root/build/appimage-extraction-$arch.log")
appdir="$work/extracted/squashfs-root"
test "$(cat "$appdir/usr/bin/release-version.txt")" = "v$version"
cmp scripts/install-spritedawg.sh "$appdir/usr/bin/update-spritedawg.sh"
cmp art/spritedawg-256.png "$appdir/usr/share/icons/hicolor/256x256/apps/org.pocketpixel.SpriteDawg.png"
cmp art/spritedawg.svg "$appdir/usr/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg"
cmp linux/packaging/org.pocketpixel.SpriteDawg.xml "$appdir/usr/share/mime/packages/org.pocketpixel.SpriteDawg.xml"
desktop-file-validate "$appdir/usr/share/applications/org.pocketpixel.SpriteDawg.desktop"
export LD_LIBRARY_PATH="$appdir/usr/bin/lib:$appdir/usr/lib"
ldd "$appdir/usr/bin/spritedawg" > "build/appimage-libraries-$arch.log"
! grep -q 'not found' "build/appimage-libraries-$arch.log"
grep 'libgtk-3.so' "build/appimage-libraries-$arch.log" | grep -F "$appdir/"
while IFS= read -r -d '' library; do
  if file "$library" | grep -q ELF; then
    dependencies=$(ldd "$library" 2>&1)
    if grep -q 'not found' <<< "$dependencies"; then echo "$library: $dependencies" >&2; exit 1; fi
  fi
done < <(find "$appdir/usr/bin/lib" -type f -name '*.so*' -print0)
# Exercise actual packaged AVIF bytes and other exports with independent decoders.
dart tool/image_export_interop.dart build/appimage-export-interop "$appdir/usr/bin/lib/libflutter_avif.so"
python3 scripts/check-image-exports.py build/appimage-export-interop --require-avif
unset LD_LIBRARY_PATH
python3 scripts/check-window-icon.py prepare art/spritedawg-256.png "$work/expected-icon.json"
# Flutter shows this GTK window only after its first rendered frame. The KDE
# environment and empty home test the explicit PNG fallback without theme setup.
for mode in extraction fuse; do
  if [[ "$mode" == fuse && ! -w /dev/fuse ]]; then
    echo 'FUSE mount smoke not available on this runner; extraction-and-run is required and tested.'
    continue
  fi
  home="$work/home-$mode"
  mkdir -p "$home"
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
    XDG_CURRENT_DESKTOP=KDE GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
    dbus-run-session -- xvfb-run -a bash scripts/smoke-appimage-window.sh \
      "$work/portable with spaces/SpriteDawg.AppImage" "$mode" "build/appimage-ui-$arch-$mode.log" "$work/expected-icon.json" "$version"
done
