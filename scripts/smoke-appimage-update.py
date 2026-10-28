#!/usr/bin/env python3
"""Exercise the real updater against a running CI AppImage without network access.

Use a same-version, byte-identical reinstall: the actual outer AppImage inode is
replaced while the GUI is running, in both mounted and extraction-and-run modes.
The mock transport substitutes local CI bytes only; verification/publication use
the production installer unchanged.
"""
import hashlib
from pathlib import Path
import shutil
import sys
import types
from unittest.mock import patch

script = Path(__file__).with_name('install-spritedawg.sh')
updater = types.ModuleType('ci_appimage_updater')
exec(compile(script.read_text().split("<<'PYTHON'\n", 1)[1].rsplit('\nPYTHON', 1)[0], str(script), 'exec'), updater.__dict__)
target = Path(sys.argv[1])
tag = 'v' + sys.argv[2]
arch = updater.architecture()
asset = f'spritedawg-{tag}-linux-{arch}.AppImage'
with target.open('rb') as stream:
    digest = updater.hash_file(stream)
manifest = f'{digest}  {asset}\n'.encode()
info = {'tag': tag, 'arch': arch, 'asset': asset, 'assets': {asset: 'ci-image', 'SHA256SUMS': 'ci-manifest'}}


def transport(url, destination=None, limit=None):
    if url == 'ci-manifest':
        return manifest
    if url != 'ci-image' or destination is None:
        raise AssertionError('Unexpected network request in offline update smoke')
    shutil.copyfile(target, destination)
    return b''


inode = target.stat().st_ino
with patch.object(updater, 'fetch', side_effect=transport):
    updater.install(info, target.parent / 'app-support-not-touched', target, tag)
assert target.stat().st_ino != inode, 'Updater did not replace the outer AppImage'
with target.open('rb') as stream:
    assert updater.hash_file(stream) == digest, 'Replacement bytes differ'
assert not (target.parent / 'app-support-not-touched').exists(), 'Update touched app-support data'
print('Checksum-verified live AppImage replacement passed; outer pathname unchanged.')
