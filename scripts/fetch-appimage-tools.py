#!/usr/bin/env python3
"""Fetch only versioned upstream AppImage tools; verify pinned hashes before use."""
import hashlib
from pathlib import Path
import sys
import urllib.request

TOOLS = {
    'x64': ('x86_64',
            'ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0',
            'c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d',
            '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d'),
    'arm64': ('aarch64',
              'f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158',
              '620095110d693282b8ebeb244a95b5e911cf8f65f76c88b4b47d16ae6346fcff',
              '00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444'),
}
GTK_COMMIT = '7a3fbc31a9e5075073ff8790f26effbac5f84453'
GTK_SHA256 = 'b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171'


def sources(arch):
    native, appimage, deploy, runtime = TOOLS[arch]
    return [
        ('appimagetool.AppImage', f'https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-{native}.AppImage', appimage),
        ('linuxdeploy.AppImage', f'https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-{native}.AppImage', deploy),
        ('runtime', f'https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-{native}', runtime),
        ('linuxdeploy-plugin-gtk.sh', f'https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/{GTK_COMMIT}/linuxdeploy-plugin-gtk.sh', GTK_SHA256),
    ]


def main():
    arch, destination = sys.argv[1:]
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for name, url, digest in sources(arch):
        path = destination / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read(64 * 1024 * 1024 + 1)
            if len(data) > 64 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('Upstream tool checksum mismatch: ' + name)
            path.write_bytes(data)
        path.chmod(0o755)


if __name__ == '__main__':
    main()
