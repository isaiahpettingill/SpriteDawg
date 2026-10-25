#!/usr/bin/env bash
set -euo pipefail
arch=${1:-x64}
bundle="build/linux/$arch/release/bundle"
[[ -x "$bundle/spritedawg" ]]
mkdir -p "$bundle/share/applications" "$bundle/share/icons/hicolor/scalable/apps"
cp linux/packaging/org.pocketpixel.SpriteDawg.desktop "$bundle/share/applications/"
cp art/spritedawg.svg "$bundle/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg"
cp LICENSE "$bundle/LICENSE"
cat > "$bundle/install-desktop.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
base="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$base/applications" "$base/icons/hicolor/scalable/apps"
# Quote the absolute path for desktop entry Exec, including spaces.
escaped=${here//\\/\\\\}; escaped=${escaped//\"/\\\"}; escaped=${escaped//\$/\\\$}; escaped=${escaped//\`/\\\`}
escaped=${escaped//%/%%}; escaped=${escaped//&/\\&}; escaped=${escaped//|/\\|}
sed "s|^Exec=.*|Exec=\"$escaped/spritedawg\"|" "$here/share/applications/org.pocketpixel.SpriteDawg.desktop" > "$base/applications/org.pocketpixel.SpriteDawg.desktop"
cp "$here/share/icons/hicolor/scalable/apps/org.pocketpixel.SpriteDawg.svg" "$base/icons/hicolor/scalable/apps/"
echo "SpriteDawg desktop entry installed. Keep this application folder in place."
INSTALL
chmod +x "$bundle/install-desktop.sh"
tar -czf "build/spritedawg-linux-$arch.tar.gz" -C "$bundle" .

sha256sum "build/spritedawg-linux-$arch.tar.gz" > "build/spritedawg-linux-$arch.tar.gz.sha256"
