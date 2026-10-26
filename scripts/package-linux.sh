#!/usr/bin/env bash
set -euo pipefail
arch=${1:-x64}
bundle="build/linux/$arch/release/bundle"
[[ -x "$bundle/spritedawg" ]]
mkdir -p "$bundle/share/mime/packages" "$bundle/share/applications" "$bundle/share/icons/hicolor/scalable/apps"
cp linux/packaging/org.pocketpixel.SpriteDawg.desktop "$bundle/share/applications/"
cp art/spritedawg.svg "$bundle/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg"
cp linux/packaging/org.pocketpixel.SpriteDawg.xml "$bundle/share/mime/packages/"
cp LICENSE "$bundle/LICENSE"
cat > "$bundle/install-desktop.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}"
command -v update-mime-database >/dev/null || { echo "Install shared-mime-info, then rerun this installer." >&2; exit 1; }
command -v update-desktop-database >/dev/null || { echo "Install desktop-file-utils, then rerun this installer." >&2; exit 1; }
mkdir -p "$base/mime/packages" "$base/applications" "$base/icons/hicolor/scalable/apps"
# Quote the absolute path for desktop entry Exec, including spaces.
escaped=${here//\\/\\\\}; escaped=${escaped//\"/\\\"}; escaped=${escaped//\$/\\\$}; escaped=${escaped//\`/\\\`}
escaped=${escaped//%/%%}; escaped=${escaped//&/\\&}; escaped=${escaped//|/\\|}
sed "s|^Exec=.*|Exec=\"$escaped/spritedawg\" %F|" "$here/share/applications/org.pocketpixel.SpriteDawg.desktop" > "$base/applications/org.pocketpixel.SpriteDawg.desktop"
cp "$here/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg" "$base/icons/hicolor/scalable/apps/"
cp "$here/share/mime/packages/org.pocketpixel.SpriteDawg.xml" "$base/mime/packages/"
update-mime-database "$base/mime"
update-desktop-database "$base/applications"
echo "SpriteDawg desktop entry and Aseprite associations installed (existing defaults unchanged). Keep this application folder in place."
INSTALL
chmod +x "$bundle/install-desktop.sh"
tar -czf "build/spritedawg-linux-$arch.tar.gz" -C "$bundle" .

(cd build && sha256sum "spritedawg-linux-$arch.tar.gz" > "spritedawg-linux-$arch.tar.gz.sha256")
