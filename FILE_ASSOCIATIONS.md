# Open Aseprite projects from a file manager

Android registers SpriteDawg for `image/x-aseprite` and `application/x-aseprite`, and for `.aseprite`/`.ase` URI paths with no MIME type or `application/octet-stream`. Choose **Open with → SpriteDawg**. Both cold starts and subsequent VIEW intents open additional document tabs without replacing dirty work. The full Aseprite decoder validates content before adding a document. Files opened via VIEW use Save As because many providers grant read-only access. No storage-wide permission is requested.

Some Android providers send only an opaque content URI and `application/octet-stream`, without a filename in the URI. Android cannot match the filename in that case; use SpriteDawg's Open picker instead. The app intentionally does not claim every binary file. Association availability is provider-dependent; physical-device validation is not claimed.

Linux: the AppImage contains the unique `org.pocketpixel.SpriteDawg` desktop ID,
original SpriteDawg icon, and `.aseprite`/`.ase` MIME definitions. Launching a portable
AppImage does not change your desktop configuration. Run the optional release
`install-spritedawg.sh` once for per-user launcher/MIME registration; the script
also migrates old tar launchers without deleting their folders or user data.
`shared-mime-info` and `desktop-file-utils` allow immediate cache refresh. It
**does not change your default application**. Select SpriteDawg in Open With;
optionally choose it as default yourself. `%F` passes multiple local paths safely.
A running instance receives later opens through GApplication and queues them until
Flutter is ready. Non-local URLs are refused, not downloaded. The application uses
the bundled PNG for KDE/X11 window icons even before launcher registration, avoiding
unrelated theme icons with generic names.

File content is validated, not trusted because of its extension. Existing session limits and recovery safeguards still apply. Failures show an error without replacing another document. Save important work separately; association registration is not a guarantee of every desktop/provider's file manager behavior.
