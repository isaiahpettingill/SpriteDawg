#!/usr/bin/env python3
"""Keep distro copyright/source metadata with libraries bundled by linuxdeploy."""
from pathlib import Path
import re
import shutil
import subprocess
import sys

appdir = Path(sys.argv[1])
licenses = appdir / 'usr/share/licenses'
licenses.mkdir(parents=True, exist_ok=True)
packages = set()
for library in (appdir / 'usr/lib').rglob('*.so*'):
    result = subprocess.run(['dpkg-query', '-S', '*/' + library.name], capture_output=True, text=True)
    for line in result.stdout.splitlines():
        package, _, _ = line.partition(': ')
        for item in package.split(', '):
            if re.fullmatch(r'[a-z0-9][a-z0-9+.-]*(?::[a-z0-9-]+)?', item):
                packages.add(item)
records = []
for package in sorted(packages):
    copyright = Path('/usr/share/doc') / package.split(':')[0] / 'copyright'
    if copyright.is_file():
        folder = licenses / package.replace(':', '-')
        folder.mkdir(exist_ok=True)
        shutil.copyfile(copyright, folder / 'copyright')
    records.append(subprocess.check_output([
        'dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n', package], text=True))
(licenses / 'ubuntu-packages.tsv').write_text(''.join(records))
shutil.copytree('LICENSES', licenses / 'spritedawg', dirs_exist_ok=True)
shutil.copyfile('LICENSE', licenses / 'spritedawg/LICENSE')
shutil.copyfile('packages/spritedawg_avif_linux/THIRD_PARTY_NOTICES.txt', licenses / 'spritedawg/AVIF.txt')
(licenses / 'README.txt').write_text(
    'SpriteDawg is MIT licensed. Bundled libraries retain their own licenses.\n'
    'Ubuntu 24.04 source package names/versions are in ubuntu-packages.tsv.\n'
    'Matching source: https://launchpad.net/ubuntu/+source/PACKAGE/VERSION\n'
    'With Ubuntu deb-src enabled: apt-get source SOURCE_PACKAGE=SOURCE_VERSION\n'
    'Build recipe: https://github.com/isaiahpettingill/SpriteDawg/blob/main/scripts/package-linux.sh\n'
    'The AppImage can be extracted with --appimage-extract to inspect or replace\n'
    'its dynamically linked libraries and launch squashfs-root/AppRun.\n'
    'AppImage runtime source/license: https://github.com/AppImage/type2-runtime/tree/20251108\n')
