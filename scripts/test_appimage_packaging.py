"""Offline packaging-contract tests; native AppImage and GUI tests run in CI."""
import hashlib
import importlib.util
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('appimage_tools', ROOT / 'scripts/fetch-appimage-tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class AppImagePackagingTests(unittest.TestCase):
    def test_both_architectures_have_versioned_verified_official_tools(self):
        for arch in ('x64', 'arm64'):
            sources = tools.sources(arch)
            self.assertEqual(len(sources), 4)
            for name, url, checksum in sources:
                self.assertRegex(checksum, r'^[a-f0-9]{64}$')
                self.assertNotIn('/continuous/', url)
                self.assertTrue(url.startswith(('https://github.com/AppImage/', 'https://github.com/linuxdeploy/',
                                                'https://raw.githubusercontent.com/linuxdeploy/')))

    def test_release_contract_only_appimages_and_existing_android(self):
        workflow = (ROOT / '.github/workflows/android.yml').read_text()
        self.assertNotIn('.tar.gz', workflow)
        for architecture in ('x64', 'arm64'):
            self.assertIn('arch: ' + architecture, workflow)
        self.assertIn('sha256sum *.apk *.AppImage *.sh > SHA256SUMS', workflow)
        self.assertIn('scripts/smoke-appimage.sh', workflow)
        self.assertIn('spritedawg-android-signed', workflow)
        self.assertIn('apksigner', workflow)
        self.assertIn('cp scripts/install-spritedawg.sh release-assets/install-spritedawg.sh', workflow)

    def test_package_preserves_flutter_layout_and_unique_metadata(self):
        arch = 'arm64' if platform.machine() == 'aarch64' else 'x64'
        with tempfile.TemporaryDirectory(prefix='appimage package ') as temp:
            root = Path(temp)
            for path in ['scripts/package-linux.sh', 'scripts/install-spritedawg.sh',
                         'linux/packaging', 'art', 'LICENSE']:
                source, target = ROOT / path, root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.is_dir():
                    shutil.copytree(source, target)
                else:
                    shutil.copyfile(source, target)
            (root / 'scripts/appimage-licenses.py').write_text('# offline fixture; do not query host packages\n')
            (root / 'scripts/fetch-appimage-tools.py').write_text('''from pathlib import Path
import sys
root = Path(sys.argv[2]); root.mkdir(parents=True)
(root / 'runtime').write_text('pinned runtime fixture')
(root / 'linuxdeploy.AppImage').write_text(''' + repr('''#!/bin/bash
while [[ "$1" != --appdir ]]; do shift; done
appdir=$2
mkdir -p "$appdir/apprun-hooks"
echo 'export GDK_BACKEND=x11 # upstream' > "$appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh"
''') + ''')
(root / 'appimagetool.AppImage').write_text(''' + repr('''#!/bin/bash
[[ "$1" == --runtime-file && -f "$2" && -d "$3" ]]
printf 'mock image' > "$4"
''') + ''')
for path in root.glob('*.AppImage'): path.chmod(0o755)
''')
            bundle = root / f'build/linux/{arch}/release/bundle'
            (bundle / 'lib').mkdir(parents=True)
            (bundle / 'data/flutter_assets').mkdir(parents=True)
            (bundle / 'spritedawg').write_text('not executed')
            (bundle / 'spritedawg').chmod(0o755)
            (bundle / 'lib/libflutter_avif.so').write_bytes(b'codec')
            (bundle / 'data/flutter_assets/fixture').write_bytes(b'flutter assets')
            # This is a packaging-contract fixture, not native tool validation.
            # The version-planning job intentionally has no GTK/desktop packages.
            commands = root / 'fixture-bin'
            commands.mkdir()
            validator = commands / 'desktop-file-validate'
            validator.write_text('#!/bin/sh\nexit 0\n')
            validator.chmod(0o755)
            result = subprocess.run(
                ['bash', 'scripts/package-linux.sh', arch, '0.3.99'], cwd=root,
                env={**os.environ, 'PATH': str(commands) + ':' + os.environ['PATH']},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            appdir = root / f'build/SpriteDawg-{arch}.AppDir'
            self.assertEqual((appdir / 'usr/bin/release-version.txt').read_text(), 'v0.3.99\n')
            self.assertEqual((appdir / 'usr/bin/data/flutter_assets/fixture').read_bytes(), b'flutter assets')
            self.assertEqual((appdir / 'usr/bin/update-spritedawg.sh').read_bytes(), (ROOT / 'scripts/install-spritedawg.sh').read_bytes())
            self.assertNotIn('export GDK_BACKEND=x11', (appdir / 'apprun-hooks/linuxdeploy-plugin-gtk.sh').read_text())
            image = root / f'build/spritedawg-linux-{arch}.AppImage'
            manifest = image.with_suffix('.AppImage.sha256').read_text()
            self.assertEqual(manifest, hashlib.sha256(image.read_bytes()).hexdigest() + '  ' + image.name + '\n')
            self.assertEqual(list((root / 'build').glob('*.tar.gz')), [])
            for size in ('16', '22', '24', '32', '48', '64', '256'):
                self.assertTrue((appdir / f'usr/share/icons/hicolor/{size}x{size}/apps/org.pocketpixel.SpriteDawg.png').is_file())


if __name__ == '__main__':
    unittest.main()
