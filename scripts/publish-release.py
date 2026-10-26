#!/usr/bin/env python3
"""Publish verified CI artifacts without replacing tags or existing assets.

Requires gh authentication via its normal environment. Never prints credentials.
Reruns resume a draft; already-published matching releases are read-only successes.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def gh(*args, binary=False):
    result = subprocess.run(['gh', *args], check=True, capture_output=True)
    return result.stdout if binary else result.stdout.decode()


def api(path, *args):
    return json.loads(gh('api', path, *args))


def version(tag):
    match = re.fullmatch(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag)
    if not match:
        raise ValueError('Release tag must be a stable vMAJOR.MINOR.PATCH version')
    return tuple(map(int, match.groups()))


def local_assets(directory, tag):
    version(tag)
    expected = {f'spritedawg-{tag}-android-{abi}.apk' for abi in
                ('armeabi-v7a', 'arm64-v8a', 'x86_64')}
    expected.update(f'spritedawg-{tag}-linux-{arch}.tar.gz' for arch in ('x64', 'arm64'))
    directory = Path(directory)
    files = {p.name: p for p in directory.iterdir()}
    if set(files) != expected | {'SHA256SUMS'}:
        raise ValueError('Expected exactly three APKs, two Linux archives and SHA256SUMS')
    if any(p.is_symlink() or not p.is_file() or p.stat().st_size == 0 for p in files.values()):
        raise ValueError('Release assets must be nonempty regular files, not symlinks')
    manifest = {}
    for line in files['SHA256SUMS'].read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._-]+)', line)
        if not match or match[2] in manifest:
            raise ValueError('Malformed or duplicate checksum entry')
        manifest[match[2]] = match[1]
    if set(manifest) != expected:
        raise ValueError('Checksum manifest must cover exactly the five platform assets')
    hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()}
    if any(hashes[name] != digest for name, digest in manifest.items()):
        raise ValueError('Local asset checksum mismatch')
    return files, hashes


def tag_commit(repo, tag):
    refs = api(f'repos/{repo}/git/matching-refs/tags/{tag}')
    matches = [r for r in refs if r['ref'] == f'refs/tags/{tag}']
    if not matches:
        return None
    obj = matches[0]['object']
    for _ in range(10):
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            break
        obj = api(f'repos/{repo}/git/tags/{obj["sha"]}')['object']
    raise ValueError('Tag does not resolve to a commit')


def release_list(repo):
    pages = api(f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp')
    return [release for page in pages for release in page]


def verify_asset(repo, asset, digest):
    remote = asset.get('digest')
    if not remote:
        data = gh('api', f'repos/{repo}/releases/assets/{asset["id"]}',
                  '-H', 'Accept: application/octet-stream', binary=True)
        remote = 'sha256:' + hashlib.sha256(data).hexdigest()
    if remote != 'sha256:' + digest:
        raise ValueError(f'Existing asset differs; refusing overwrite: {asset["name"]}')


def publish(repo, sha, tag, assets, notes):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository')
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Expected full lowercase commit SHA')
    files, hashes = local_assets(assets, tag)
    if not Path(notes).is_file():
        raise ValueError('Release notes file is missing')
    commit = tag_commit(repo, tag)
    if commit is not None and commit != sha:
        raise ValueError('Existing tag points to a different commit; refusing mutation')
    releases = release_list(repo)
    matches = [r for r in releases if r['tag_name'] == tag]
    if len(matches) > 1:
        raise ValueError('Duplicate release tag')
    release = matches[0] if matches else None
    if release is None:
        gh('release', 'create', tag, '--repo', repo, '--target', sha, '--draft',
           '--title', f'SpriteDawg {tag}', '--notes-file', str(notes))
        release = next(r for r in release_list(repo) if r['tag_name'] == tag)
    if release['draft'] and release['target_commitish'] != sha:
        raise ValueError('Existing draft is not pinned to the expected commit')
    if not release['draft'] and commit != sha:
        raise ValueError('Published release tag must resolve to expected commit')
    remote_assets = {a['name']: a for a in release['assets']}
    if not release['draft']:
        # A rerun can rebuild different but valid bytes. Published assets are
        # immutable and authoritative: validate their own manifest, not the rebuild.
        if set(remote_assets) != set(files) or len(remote_assets) != len(release['assets']):
            raise ValueError('Published release has an invalid asset set')
        checksum_asset = remote_assets['SHA256SUMS']
        data = gh('api', f'repos/{repo}/releases/assets/{checksum_asset["id"]}',
                  '-H', 'Accept: application/octet-stream', binary=True)
        remote_hashes = {}
        for line in data.decode().splitlines():
            match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._-]+)', line)
            if not match or match[2] in remote_hashes:
                raise ValueError('Published checksum manifest is malformed')
            remote_hashes[match[2]] = match[1]
        if set(remote_hashes) != set(files) - {'SHA256SUMS'}:
            raise ValueError('Published manifest does not cover all platform assets')
        remote_hashes['SHA256SUMS'] = hashlib.sha256(data).hexdigest()
        for name, asset in remote_assets.items():
            verify_asset(repo, asset, remote_hashes[name])
        return release['html_url']
    if len(remote_assets) != len(release['assets']) or not set(remote_assets) <= set(files):
        raise ValueError('Unexpected or duplicate remote release assets')
    for name, asset in remote_assets.items():
        verify_asset(repo, asset, hashes[name])
    missing = sorted(set(files) - set(remote_assets))
    if missing and not release['draft']:
        raise ValueError('Published release incomplete; refusing to modify it')
    for name in missing:
        gh('release', 'upload', tag, str(files[name]), '--repo', repo)
    # Refetch and verify every uploaded byte before publishing, including manifest.
    current = api(f'repos/{repo}/releases/{release["id"]}')
    if {a['name'] for a in current['assets']} != set(files) or len(current['assets']) != len(files):
        raise ValueError('Release asset set changed during verification')
    for asset in current['assets']:
        verify_asset(repo, asset, hashes[asset['name']])
    if current['draft']:
        commit = tag_commit(repo, tag)
        if commit is not None and commit != sha:
            raise ValueError('Tag changed before publication')
        # Re-read release ordering. GitHub legacy ordering avoids forcing an older
        # finishing run over a newer version if concurrent jobs race this check.
        newer = False
        for other in release_list(repo):
            if other['draft'] or other.get('prerelease'):
                continue
            try:
                newer |= version(other['tag_name']) > version(tag)
            except ValueError:
                continue
        api(f'repos/{repo}/releases/{release["id"]}', '--method', 'PATCH',
            '-F', 'draft=false', '-f', f'make_latest={"false" if newer else "legacy"}')
    final = api(f'repos/{repo}/releases/{release["id"]}')
    if final['draft'] or tag_commit(repo, tag) != sha:
        raise ValueError('Publication verification failed')
    return final['html_url']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('repo', 'sha', 'tag', 'assets', 'notes'):
        parser.add_argument('--' + arg, required=True)
    args = parser.parse_args()
    print(publish(**vars(args)))


if __name__ == '__main__':
    main()
