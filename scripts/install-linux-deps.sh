#!/usr/bin/env bash
# Hosted runners already contain most tools. Don't refresh every APT source if
# every required package is installed. Limit transient mirror waits and retries.
set -euo pipefail
packages=(clang cmake ninja-build meson nasm pkg-config libgtk-3-dev libstdc++-12-dev librsvg2-dev libgirepository1.0-dev desktop-file-utils shared-mime-info patchelf squashfs-tools xvfb xauth xdotool x11-utils dbus-x11)
# Hosted images also provide tools outside dpkg (for example /usr/local/bin/cmake).
# Reuse only commands that report a compatible version; development headers must
# still be installed through their distro package.
tool_ready() {
  local command=$1 minimum=$2 found
  command -v "$command" >/dev/null 2>&1 || return 1
  found=$("$command" --version 2>/dev/null | head -n 1) || return 1
  python3 - "$minimum" "$found" <<'VERSION'
import re, sys
match = re.search(r'(?<![0-9])([0-9]+\.[0-9]+(?:\.[0-9]+)?)', sys.argv[2])
if not match:
    raise SystemExit(1)
def parts(value):
    return tuple((list(map(int, value.split('.'))) + [0, 0, 0])[:3])
raise SystemExit(0 if parts(match.group(1)) >= parts(sys.argv[1]) else 1)
VERSION
}
missing=()
for package in "${packages[@]}"; do
  case "$package" in
    clang) tool_ready clang 7.0 && continue ;;
    cmake) tool_ready cmake 3.13 && continue ;;
    ninja-build) tool_ready ninja 1.8 && continue ;;
    pkg-config) tool_ready pkg-config 0.29 && continue ;;
    meson) tool_ready meson 0.64 && continue ;;
    nasm) tool_ready nasm 2.14 && continue ;;
  esac
  if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" != 'install ok installed' ]]; then
    missing+=("$package")
  fi
done
if ((${#missing[@]} == 0)); then
  echo 'Linux build dependencies are already installed.'
  exit 0
fi
for attempt in 1 2; do
  if timeout 90s sudo apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o APT::Update::Error-Mode=any update &&
     timeout 300s sudo apt-get -o DPkg::Lock::Timeout=30 -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install --no-install-recommends -y "${missing[@]}"; then
    exit 0
  fi
  if [[ "$attempt" == 1 ]]; then sleep 5; fi
done
echo 'Linux dependency mirror failed twice within bounded time; rerun this job.' >&2
exit 1
