#!/usr/bin/env bash
# SpriteDawg per-user Linux installer/updater. Requires Python 3.9+.
set -euo pipefail
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }
exec python3 - "$@" <<'PYTHON'
"""Download only official stable releases; never run scripts from the archive."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid

REPO = 'isaiahpettingill/SpriteDawg'
API = 'https://api.github.com/repos/' + REPO + '/releases/'
HOSTS = {'api.github.com', 'github.com', 'release-assets.githubusercontent.com',
         'objects.githubusercontent.com'}
MAX_DOWNLOAD = 512 * 1024 * 1024
MAX_UNPACKED = 2 * 1024 * 1024 * 1024
APP_ID = 'org.pocketpixel.SpriteDawg'


def version(tag):
    if not isinstance(tag, str) or not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag):
        raise ValueError('Not a stable SpriteDawg release version')
    return tuple(int(n) for n in tag[1:].split('.'))


def architecture(machine=None):
    machine = machine or platform.machine()
    if machine in ('x86_64', 'amd64'):
        return 'x64'
    if machine in ('aarch64', 'arm64'):
        return 'arm64'
    raise ValueError('Only Linux x64 and ARM64 are supported')


def validate_url(url):
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != 'https' or parts.hostname not in HOSTS or
            parts.username or parts.password or parts.port not in (None, 443)):
        raise ValueError('Release download left the trusted GitHub hosts')
    return url


class TrustedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, destination=None, limit=2 * 1024 * 1024):
    request = urllib.request.Request(validate_url(url), headers={
        'Accept': 'application/vnd.github+json', 'User-Agent': 'SpriteDawg-Linux-Updater'})
    opener = urllib.request.build_opener(TrustedRedirect())
    try:
        with opener.open(request, timeout=30) as response:
            validate_url(response.url)
            length = response.headers.get('Content-Length')
            if length and int(length) > limit:
                raise ValueError('Release download exceeds size limit')
            total, chunks = 0, []
            with (open(destination, 'wb') if destination else contextlib.nullcontext()) as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > limit:
                        raise ValueError('Release download exceeds size limit')
                    if output:
                        output.write(chunk)
                    else:
                        chunks.append(chunk)
            return b''.join(chunks)
    except urllib.error.HTTPError as error:
        if error.code in (403, 429):
            raise ValueError('GitHub rate limit reached. Try again later.') from error
        raise ValueError('GitHub release request failed (HTTP %s)' % error.code) from error


def release(tag=None, arch=None):
    if tag:
        version(tag)
    data = json.loads(fetch(API + ('tags/' + tag if tag else 'latest')))
    actual = data.get('tag_name')
    version(actual)
    if data.get('draft') or data.get('prerelease') or (tag and actual != tag):
        raise ValueError('Expected a published stable release')
    arch = arch or architecture()
    name = 'spritedawg-%s-linux-%s.tar.gz' % (actual, arch)
    assets = {}
    for item in data.get('assets', []):
        key = item.get('name')
        if key in (name, 'SHA256SUMS'):
            if key in assets or item.get('state') != 'uploaded':
                raise ValueError('Release has incomplete or duplicate assets')
            expected = 'https://github.com/%s/releases/download/%s/%s' % (REPO, actual, key)
            if item.get('browser_download_url') != expected:
                raise ValueError('Unexpected release asset location')
            assets[key] = expected
    if set(assets) != {name, 'SHA256SUMS'}:
        raise ValueError('This release has no complete Linux %s download' % arch)
    return {'tag': actual, 'arch': arch, 'asset': name, 'assets': assets}


def checksum(manifest, name):
    matches = []
    for line in manifest.decode('ascii').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._-]+)', line)
        if not match:
            raise ValueError('Malformed release checksums')
        if match[2] == name:
            matches.append(match[1])
    if len(matches) != 1:
        raise ValueError('Missing or duplicate archive checksum')
    return matches[0]


def unpack(archive, target):
    """No links/devices/traversal/duplicates; bounded expanded bytes and entries."""
    with tarfile.open(archive, 'r:gz') as source:
        seen, total = set(), 0
        members = []
        for member in source:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or '\\' in member.name or
                    any(ord(c) < 32 for c in member.name)):
                raise ValueError('Unsafe release archive path')
            relative = str(path)
            if relative == '.' and member.isdir():
                continue
            if relative in seen or not (member.isfile() or member.isdir()):
                raise ValueError('Release archive contains links or duplicate/special entries')
            seen.add(relative)
            total += member.size
            if len(seen) > 20000 or member.size < 0 or total > MAX_UNPACKED:
                raise ValueError('Release archive exceeds extraction limits')
            members.append((member, path))
        for member, relative in members:
            destination = target.joinpath(*relative.parts)
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as input_file, open(destination, 'xb') as output:
                    shutil.copyfileobj(input_file, output)
                destination.chmod(0o755 if member.mode & 0o111 else 0o644)


def verify_bundle(bundle, info):
    executable = bundle / 'spritedawg'
    with executable.open('rb') as stream:
        header = stream.read(20)
    expected_machine = 62 if info['arch'] == 'x64' else 183
    if (len(header) < 20 or header[:4] != b'\x7fELF' or header[4:6] != b'\x02\x01' or
            int.from_bytes(header[18:20], 'little') != expected_machine or
            not executable.stat().st_mode & stat.S_IXUSR):
        raise ValueError('Release executable does not match this architecture')
    recorded = (bundle / 'release-version.txt').read_text().strip()
    if recorded != info['tag']:
        raise ValueError('Bundle version does not match the selected release')
    for file in ('share/icons/hicolor/scalable/apps/' + APP_ID + '.svg',
                 'share/mime/packages/' + APP_ID + '.xml', 'update-spritedawg.sh'):
        if not (bundle / file).is_file():
            raise ValueError('Release bundle is missing required installation files')


def desktop_quote(value):
    if any(ord(c) < 32 for c in value):
        raise ValueError('Installation path contains control characters')
    # Desktop entry string escaping is applied after Exec argument escaping.
    escaped = value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$')
    return '"' + escaped.replace('\\', '\\\\').replace('%', '%%') + '"'


def desktop_text(current):
    return ('[Desktop Entry]\nType=Application\nName=SpriteDawg\n'
            'Comment=Draw pixel art and edit Aseprite projects\nExec=%s %%F\n'
            'Icon=%s\nTerminal=false\nCategories=Graphics;2DGraphics;\n'
            'StartupWMClass=%s\nX-Purism-FormFactor=Workstation;Mobile;\n'
            'MimeType=image/x-aseprite;application/x-aseprite;\n') % (
                desktop_quote(str(current / 'spritedawg')), APP_ID, APP_ID)


def atomic_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.spritedawg-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def activate(root, bundle, data_home):
    current = root / 'current'
    if current.exists() and not current.is_symlink():
        raise ValueError('Install location is not managed by the SpriteDawg updater')
    previous = os.readlink(current) if current.is_symlink() else None
    files = {
        data_home / 'applications' / (APP_ID + '.desktop'): desktop_text(current).encode(),
        data_home / 'icons/hicolor/scalable/apps' / (APP_ID + '.svg'):
            (bundle / ('share/icons/hicolor/scalable/apps/' + APP_ID + '.svg')).read_bytes(),
        data_home / 'mime/packages' / (APP_ID + '.xml'):
            (bundle / ('share/mime/packages/' + APP_ID + '.xml')).read_bytes(),
    }
    old = {}
    for path in files:
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError('Refusing to replace a non-regular desktop registration file')
        old[path] = path.read_bytes() if path.exists() else None
    link = root / ('.current-' + uuid.uuid4().hex)
    try:
        for path, data in files.items():
            atomic_bytes(path, data)
        link.symlink_to(bundle.relative_to(root))
        os.replace(link, current)
    except Exception:
        # Restore registration even if publication failed halfway through.
        for path, data in old.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                atomic_bytes(path, data)
        if previous is not None and (not current.is_symlink() or os.readlink(current) != previous):
            link.unlink(missing_ok=True)
            link.symlink_to(previous)
            os.replace(link, current)
        raise
    finally:
        link.unlink(missing_ok=True)


def install(info, data_home):
    data_home = data_home.expanduser().absolute()
    desktop_quote(str(data_home))
    root = data_home / 'spritedawg'
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.update.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another SpriteDawg update is in progress') from error
        installed = root / 'current/release-version.txt'
        if installed.is_file() and version(installed.read_text().strip()) > version(info['tag']):
            raise ValueError('Refusing to downgrade the installed SpriteDawg')
        (root / 'versions').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.download-', dir=root) as work:
            work = Path(work)
            manifest = fetch(info['assets']['SHA256SUMS'])
            digest = checksum(manifest, info['asset'])
            archive = work / 'release.tar.gz'
            fetch(info['assets'][info['asset']], archive, MAX_DOWNLOAD)
            with archive.open('rb') as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hash_file(stream)
            if actual != digest:
                raise ValueError('Download checksum mismatch; installed app was not changed')
            staged = work / 'bundle'
            staged.mkdir()
            unpack(archive, staged)
            verify_bundle(staged, info)
            # Unique directories retain old files while a running app still uses them.
            target = root / 'versions' / (info['tag'] + '-' + uuid.uuid4().hex)
            os.replace(staged, target)
            try:
                activate(root, target, data_home)
            except Exception:
                shutil.rmtree(target)
                raise
        for command, directory in [('update-mime-database', data_home / 'mime'),
                                   ('update-desktop-database', data_home / 'applications')]:
            if shutil.which(command):
                try:
                    result = subprocess.run([command, str(directory)], capture_output=True, timeout=30)
                    if result.returncode:
                        print('Warning: refresh desktop caches at your next login.', file=sys.stderr)
                except (OSError, subprocess.TimeoutExpired):
                    print('Warning: refresh desktop caches at your next login.', file=sys.stderr)
        return root / 'current/spritedawg'


def hash_file(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description='Install/update SpriteDawg for the current Linux user.')
    parser.add_argument('--check', action='store_true', help='Print latest stable release metadata, without installing')
    parser.add_argument('--version', help='Install exactly this stable vMAJOR.MINOR.PATCH release')
    args = parser.parse_args()
    if sys.platform != 'linux':
        raise ValueError('This installer is for Linux')
    if os.geteuid() == 0 and not args.check:
        raise ValueError('Run this installer as your normal user, not with sudo')
    info = release(args.version)
    if args.check:
        print(json.dumps({'tag': info['tag'], 'arch': info['arch']}))
        return
    data_home = Path(os.environ.get('XDG_DATA_HOME') or str(Path.home() / '.local/share'))
    if not data_home.is_absolute():
        raise ValueError('XDG_DATA_HOME must be an absolute path')
    installed = install(info, data_home)
    print(json.dumps({'tag': info['tag'], 'executable': str(installed)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('SpriteDawg update failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
PYTHON
