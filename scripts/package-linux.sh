#!/usr/bin/env bash
set -euo pipefail
arch=${1:-x64}
version=${2:?Pass the tested release version (without v)}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
case "$arch:$(uname -m)" in
  x64:x86_64) native=x86_64 ;;
  arm64:aarch64) native=aarch64 ;;
  *) echo 'Build AppImages on their matching native architecture.' >&2; exit 1 ;;
esac
bundle="build/linux/$arch/release/bundle"
[[ -x "$bundle/spritedawg" && -s "$bundle/lib/libflutter_avif.so" ]]
tools="$(pwd)/build/appimage-tools-$arch"
python3 scripts/fetch-appimage-tools.py "$arch" "$tools"
appdir="$(pwd)/build/SpriteDawg-$arch.AppDir"
rm -rf -- "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/mime/packages" "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/scalable/apps" "$appdir/usr/share/icons/hicolor/256x256/apps"
# Flutter needs data/, lib/, native assets and updater next to its real executable.
cp -a "$bundle/." "$appdir/usr/bin/"
cp scripts/install-spritedawg.sh "$appdir/usr/bin/update-spritedawg.sh"
printf 'v%s\n' "$version" > "$appdir/usr/bin/release-version.txt"
cp LICENSE "$appdir/usr/bin/LICENSE"
cp linux/packaging/org.pocketpixel.SpriteDawg.desktop "$appdir/usr/share/applications/"
cp linux/packaging/org.pocketpixel.SpriteDawg.xml "$appdir/usr/share/mime/packages/"
cp art/spritedawg.svg "$appdir/usr/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg"
cp art/spritedawg-256.png "$appdir/usr/share/icons/hicolor/256x256/apps/org.pocketpixel.SpriteDawg.png"
for size in 16 22 24 32 48 64; do
  mkdir -p "$appdir/usr/share/icons/hicolor/${size}x${size}/apps"
  cp "art/icons/$size/spritedawg.png" "$appdir/usr/share/icons/hicolor/${size}x${size}/apps/org.pocketpixel.SpriteDawg.png"
done
# Explicitly deploy dlopen codecs/native assets, not only ELF DT_NEEDED entries.
libraries=()
while IFS= read -r -d '' library; do libraries+=(--library "$library"); done < <(find "$appdir/usr/bin/lib" -name '*.so*' -type f -print0)
export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3 NO_STRIP=1
"$tools/linuxdeploy.AppImage" --appdir "$appdir" --executable "$appdir/usr/bin/spritedawg" \
  --desktop-file "$appdir/usr/share/applications/org.pocketpixel.SpriteDawg.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/org.pocketpixel.SpriteDawg.png" \
  "${libraries[@]}" --plugin gtk
# Keep upstream GTK resources/module setup but honor the host's Wayland/X11 choice.
sed -i '/^export GDK_BACKEND=x11 /d' "$appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh"
# Use our launcher so Flutter's adjacent assets and the self-updater retain identity.
rm -f "$appdir/AppRun"
cp linux/packaging/AppRun "$appdir/AppRun"
chmod 755 "$appdir/AppRun" "$appdir/usr/bin/update-spritedawg.sh"
desktop-file-validate "$appdir/usr/share/applications/org.pocketpixel.SpriteDawg.desktop"
python3 scripts/appimage-licenses.py "$appdir"
# Never let appimagetool fetch an unpinned continuous runtime.
ARCH="$native" "$tools/appimagetool.AppImage" --runtime-file "$tools/runtime" \
  "$appdir" "build/spritedawg-linux-$arch.AppImage"
(cd build && sha256sum "spritedawg-linux-$arch.AppImage" > "spritedawg-linux-$arch.AppImage.sha256")
