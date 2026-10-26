#!/usr/bin/env bash
# Hosted runners already contain most tools. Don't refresh every APT source if
# every required package is installed. Limit transient mirror waits and retries.
set -euo pipefail
packages=(clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev)
missing=()
for package in "${packages[@]}"; do
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
     timeout 90s sudo apt-get -o DPkg::Lock::Timeout=30 -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y "${missing[@]}"; then
    exit 0
  fi
  if [[ "$attempt" == 1 ]]; then sleep 5; fi
done
echo 'Linux dependency mirror failed twice within bounded time; rerun this job.' >&2
exit 1
