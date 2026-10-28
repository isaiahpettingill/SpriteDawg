#!/usr/bin/env bash
# SpriteDawg per-user Linux installer/updater. Requires Python 3.9+.
set -euo pipefail
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }
exec python3 - "$@" <<'PYTHON'
"""Download only official stable releases; never execute downloaded code during installation."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

REPO = 'isaiahpettingill/SpriteDawg'
API = 'https://api.github.com/repos/' + REPO + '/releases/'
HOSTS = {'api.github.com', 'github.com', 'release-assets.githubusercontent.com',
         'objects.githubusercontent.com'}
MAX_DOWNLOAD = 512 * 1024 * 1024
APP_ID = 'org.pocketpixel.SpriteDawg'
ICON = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">\n<title>SpriteDawg</title>\n<desc>An original pixel dog on a warm violet tile. MIT licensed.</desc>\n<rect x="4" y="5" width="56" height="56" rx="8" fill="#000000" opacity=".2"/>\n<rect x="4" y="4" width="56" height="56" rx="8" fill="#7466a3"/>\n<path fill="#ffffff" opacity=".2" d="M12 4H52Q60 4 60 12V13Q60 5 52 5H12Q4 5 4 13V12Q4 4 12 4Z"/>\n<path d="M20,16 44,16 44,20 52,20 52,40 44,40 44,48 40,48 40,52 24,52 24,48 20,48 20,40 12,40 12,20 20,20Z" fill="#000000" opacity=".2" transform="translate(0 1)"/>\n<path d="M20,16 44,16 44,20 52,20 52,40 44,40 44,48 40,48 40,52 24,52 24,48 20,48 20,40 12,40 12,20 20,20Z" fill="#f5e6c8"/>\n<path fill="#b88a60" d="M12 20H20V40H12Z"/>\n<path fill="#b88a60" d="M44 20H52V40H44Z"/>\n<path fill="#403743" d="M24 28H28V32H24Z"/>\n<path fill="#403743" d="M36 28H40V32H36Z"/>\n<path fill="#403743" d="M28 36H36V40H28Z"/>\n<path fill="#403743" d="M30 40H34V44H30Z"/>\n<path fill="#cc7574" d="M28 44H36V48H28Z"/>\n</svg>\n'
MIME = '<?xml version="1.0" encoding="UTF-8"?>\n<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">\n  <mime-type type="image/x-aseprite">\n    <comment>Aseprite sprite project</comment>\n    <alias type="application/x-aseprite"/>\n    <glob pattern="*.aseprite"/>\n    <glob pattern="*.ase"/>\n    <magic priority="60"><match type="little16" value="0xA5E0" offset="4"/></magic>\n  </mime-type>\n</mime-info>\n'


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
    name = 'spritedawg-%s-linux-%s.AppImage' % (actual, arch)
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
        raise ValueError('Missing or duplicate AppImage checksum')
    return matches[0]


def verify_appimage(path, arch):
    with path.open('rb') as stream:
        header = stream.read(20)
    expected_machine = 62 if arch == 'x64' else 183
    if (len(header) < 20 or header[:6] != b'\x7fELF\x02\x01' or
            header[8:11] != b'AI\x02' or
            int.from_bytes(header[18:20], 'little') != expected_machine):
        raise ValueError('Release is not a type-2 AppImage for this architecture')


def desktop_quote(value):
    if any(ord(c) < 32 for c in value):
        raise ValueError('Installation path contains control characters')
    # Desktop entry string escaping is applied after Exec argument escaping.
    escaped = value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$')
    return '"' + escaped.replace('\\', '\\\\').replace('%', '%%') + '"'


def desktop_text(executable, icon):
    return ('[Desktop Entry]\nType=Application\nName=SpriteDawg\n'
            'Comment=Draw pixel art and edit Aseprite projects\nExec=%s %%F\n'
            'Icon=%s\nTerminal=false\nCategories=Graphics;2DGraphics;\n'
            'StartupWMClass=%s\nX-Purism-FormFactor=Workstation;Mobile;\n'
            'MimeType=image/x-aseprite;application/x-aseprite;\n') % (
                desktop_quote(str(executable)), str(icon).replace('\\', '\\\\'), APP_ID)


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


def validate_target(target, arch, must_exist=False):
    """Only replace an owned regular file in a private, writable directory."""
    target = Path(target)
    if not target.is_absolute() or target.resolve() != target or target.is_symlink():
        raise ValueError('Use the real, absolute AppImage path, not a symlink')
    parent = target.parent.stat()
    if (parent.st_uid != os.getuid() or parent.st_mode & 0o022 or
            not parent.st_mode & stat.S_IWUSR or not os.access(target.parent, os.W_OK)):
        raise ValueError('AppImage folder is not writable/private: %s. For an owned shared folder, remove group/other write permission (chmod go-w), or save a new copy in your own private Applications folder; do not use sudo.' % target.parent)
    if target.exists():
        status = target.lstat()
        if (not stat.S_ISREG(status.st_mode) or status.st_uid != os.getuid() or
                status.st_mode & 0o022 or not status.st_mode & stat.S_IWUSR):
            raise ValueError('AppImage is not an owned writable regular file. Save a new copy; do not use sudo.')
        verify_appimage(target, arch)
        return (status.st_dev, status.st_ino, status.st_size, status.st_mtime_ns)
    if must_exist:
        raise ValueError('Running AppImage has moved. Save a new copy and reopen it.')
    return None


def sync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def install(info, data_home, appimage=None, current_version=None):
    """Publish one AppImage atomically. Never touch drawings or app-support data."""
    data_home = data_home.expanduser().absolute()
    desktop_quote(str(data_home))
    managed = appimage is None
    if managed:
        root = data_home / 'spritedawg'
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        target = root / 'SpriteDawg.AppImage'
    else:
        target = Path(appimage)
        if current_version is None:
            raise ValueError('The running AppImage version is required')
    identity = validate_target(target, info['arch'], must_exist=not managed)
    # A stable sibling lock protects concurrent updaters even after inode replacement.
    lock_path = target.with_name('.' + target.name + '.update.lock')
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'a') as lock:
        status = os.fstat(lock.fileno())
        if (status.st_uid != os.getuid() or not stat.S_ISREG(status.st_mode) or
                status.st_nlink != 1 or status.st_mode & 0o022):
            raise ValueError('Update lock is not a private regular file owned by this user')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another SpriteDawg update is in progress') from error
        if validate_target(target, info['arch'], must_exist=not managed) != identity:
            raise ValueError('AppImage changed while preparing update; check the current version')
        version_file = target.with_name('.' + target.name + '.version')
        if version_file.is_symlink() or (version_file.exists() and not version_file.is_file()):
            raise ValueError('Unsafe version registration file')
        recorded_versions = [current_version] if current_version else []
        if version_file.is_file():
            recorded_versions.append(version_file.read_text().strip())
        legacy = data_home / 'spritedawg/current/release-version.txt'
        if managed and legacy.is_file():
            recorded_versions.append(legacy.read_text().strip())
        if any(version(recorded) > version(info['tag']) for recorded in recorded_versions):
            raise ValueError('Refusing to downgrade the installed SpriteDawg')
        # Same filesystem is essential for atomic replacement. No cross-device move.
        with tempfile.TemporaryDirectory(prefix='.spritedawg-update-', dir=target.parent) as work:
            work = Path(work)
            digest = checksum(fetch(info['assets']['SHA256SUMS']), info['asset'])
            staged = work / 'SpriteDawg.AppImage'
            fetch(info['assets'][info['asset']], staged, MAX_DOWNLOAD)
            with staged.open('rb') as stream:
                if hash_file(stream) != digest:
                    raise ValueError('Download checksum mismatch; installed app was not changed')
                os.fsync(stream.fileno())
            verify_appimage(staged, info['arch'])
            staged.chmod(0o755)
            with staged.open('rb') as stream:
                os.fsync(stream.fileno())
            files = {version_file: (info['tag'] + '\n').encode()}
            if managed:
                icon = data_home / 'icons/hicolor/scalable/apps' / (APP_ID + '.svg')
                files.update({
                    icon: ICON.encode(),
                    data_home / 'mime/packages' / (APP_ID + '.xml'): MIME.encode(),
                    data_home / 'applications' / (APP_ID + '.desktop'):
                        desktop_text(target, icon).encode(),
                })
            old = {}
            for path in files:
                if (path.resolve() != path or path.is_symlink() or
                        (path.exists() and (not path.is_file() or path.stat().st_uid != os.getuid()))):
                    raise ValueError('Refusing a symlinked or unowned desktop registration path')
                old[path] = path.read_bytes() if path.exists() else None
            if validate_target(target, info['arch'], must_exist=not managed) != identity:
                raise ValueError('AppImage changed during download; installed app was not changed')
            backup = work / 'previous.AppImage'
            if identity is not None:
                os.link(target, backup)
            published = False
            try:
                for path, data in files.items():
                    atomic_bytes(path, data)
                os.replace(staged, target)
                published = True
                sync_directory(target.parent)
            except Exception:
                if published:
                    if backup.exists():
                        os.replace(backup, target)
                    else:
                        target.unlink()
                for path, data in old.items():
                    if data is None:
                        path.unlink(missing_ok=True)
                    else:
                        atomic_bytes(path, data)
                raise
        if managed:
            for command, directory in [('update-mime-database', data_home / 'mime'),
                                       ('update-desktop-database', data_home / 'applications')]:
                if shutil.which(command):
                    try:
                        result = subprocess.run([command, str(directory)], capture_output=True, timeout=30)
                        if result.returncode:
                            print('Warning: refresh desktop caches at your next login.', file=sys.stderr)
                    except (OSError, subprocess.TimeoutExpired):
                        print('Warning: refresh desktop caches at your next login.', file=sys.stderr)
        return target


def hash_file(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description='Install/update SpriteDawg for the current Linux user.')
    parser.add_argument('--appimage', help='Replace this running AppImage in place, not its mounted AppDir')
    parser.add_argument('--current-version', help='Version of the running AppImage')
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
    installed = install(info, data_home, args.appimage, args.current_version)
    print(json.dumps({'tag': info['tag'], 'executable': str(installed)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('SpriteDawg update failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
PYTHON
