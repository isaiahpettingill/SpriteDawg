# Linux AppImage packaging

The release contract is exactly two Linux AppImages (x64 and ARM64), three existing
Android APKs, the optional standalone installer, and SHA256SUMS. Linux tar assets
are no longer produced or accepted by the publication script.

## Tool provenance

`scripts/fetch-appimage-tools.py` pins both native architectures to upstream
release assets and their published SHA-256 digests. Nothing is fetched from a
third-party binary mirror; mismatched bytes fail before execution:

- [AppImage/appimagetool 1.9.1](https://github.com/AppImage/appimagetool/releases/tag/1.9.1)
- [linuxdeploy 1-alpha-20251107-1](https://github.com/linuxdeploy/linuxdeploy/releases/tag/1-alpha-20251107-1)
- [AppImage type2-runtime 20251108](https://github.com/AppImage/type2-runtime/releases/tag/20251108)
- [Official GTK plugin at 7a3fbc31](https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/tree/7a3fbc31a9e5075073ff8790f26effbac5f84453)

The runtime is passed explicitly to appimagetool, disabling its implicit download
of a moving continuous release. Tool AppImages use extraction-and-run for CI.
The GTK plugin packages schemas, pixbuf loaders, input modules and their libraries;
its generated X11 override is removed so a caller can select Wayland or X11.
`AppRun` keeps Flutter's data/lib layout and native codec search path intact.
Upstream notices plus Ubuntu package versions/copyright files accompany libraries
under `usr/share/licenses`; the AppImage is extractable to inspect/replace them.

## Runtime and desktop identity

The build baseline is Ubuntu 24.04 for x64 and ARM64, not arbitrary old glibc
systems. Host graphics drivers/display services remain required. No root setup is
performed. FUSE-free launch: `./SpriteDawg.AppImage --appimage-extract-and-run`.
Manual extraction: `./SpriteDawg.AppImage --appimage-extract`, then
`./squashfs-root/AppRun`; this latter mode cannot self-replace the original image.

The GTK application ID, desktop filename, icon names and StartupWMClass retain
`org.pocketpixel.SpriteDawg`, preserving app-support/preferences/draft locations.
The original Papirus-guideline SpriteDawg artwork is bundled at native sizes;
no generic `aseprite`/`spritedawg` theme name is reused. The GTK runner loads the
bundled PNG explicitly for KDE/X11 taskbar fallback. The optional per-user desktop
entry uses an absolute icon path, so a theme cannot replace it by name.
MIME definitions cover `.ase` and `.aseprite`; registration never changes defaults.

## Updating and legacy migration

`APPIMAGE` identifies the outer file; `Platform.resolvedExecutable` identifies the
inner Flutter binary and its bundled updater/version. The updater never writes to
the read-only AppDir. It requires an owned writable regular target, no symlinks,
and a user-owned non-shared parent directory. It downloads into a private sibling
temporary directory, verifies exact stable release asset/checksum/type/architecture,
fsyncs, and atomically replaces the same pathname. Concurrent updaters are locked;
a changed target, failed download, invalid checksum, wrong architecture, downgrade
or failed registration leaves the old application intact. A temporary hard-link
backup supports rollback if publication fails; it is removed after success.

The old inode/mount can continue serving the running editor. Updates never quit or
restart it; save drawings and reopen when ready. Artwork, preferences and drafts
are not part of this file transaction. One small sibling version marker and lock
file are maintained, not accumulating version trees. A hard interruption can leave
an unused hidden `.spritedawg-update-*` staging directory; it is not a new install
or user data and is never automatically executed.

A fresh managed install creates its app directory with private permissions even
with umask 0002. Existing group/other-writable directories are refused with
explicit `chmod go-w` guidance; permissions are not silently broadened or changed.

Old tar-bundled updaters cannot recognize new AppImage-only releases. Run the new
release installer once to point the desktop launcher at the AppImage. It preserves
old version directories/current links and all app data; cleanup is deliberately
not automatic. Read-only locations require saving a new AppImage in your own
folder, not privilege escalation.

## Verification

Offline Python tests exercise self-replacement, old-open-inode behavior, migration,
checksum/type/architecture rejection, update races/locks, read-only/symlink paths,
downgrade prevention, disk/download/activation failures and metadata rollback.
Release tests enforce the AppImage-only asset set and checksum manifest.

Both native CI jobs build the real AppImage, check its checksum, extract it, verify
its identity/icon/MIME/updater/version, inspect library resolution, and export with
the packaged AVIF codec plus independent image decoders. Xvfb/DBus launches the
actual packaged Flutter app with an empty home and KDE environment, waits for its
first visible rendered frame, verifies WM_CLASS and a populated window icon, then
checks repeated launch routing. Extraction-and-run is mandatory; FUSE mounting is
also tested when the runner exposes usable `/dev/fuse`.

These are CI smoke checks, not physical ARM/Linux-phone, full KDE compositor or
Wayland validation. Refer to the PR's actual job results before claiming they
passed; a script being present is not evidence of a successful run.
