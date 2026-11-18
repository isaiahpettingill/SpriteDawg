# Open Aseprite projects from a file manager

On Android, select a project in your file manager and choose **Open with → SpriteDawg** or **Edit → SpriteDawg**. Both actions open a tab. SpriteDawg checks the file contents before it adds the tab.

**Save** updates the original when the file manager or the system picker grants write access. For a read-only file or an expired grant, Save opens the system **Save as** picker with the project name. After the first successful save, subsequent saves use that destination. Restored drafts still require a destination.

Some providers identify every binary download as `application/octet-stream` and give it a numeric URI. SpriteDawg accepts this type so these providers can offer it for an Aseprite project. This also puts SpriteDawg in the chooser for other binary files. It also registers for Aseprite MIME types and for visible `.aseprite` and `.ase` path extensions. If the file manager supplies neither a recognized type nor a matching path, use **Open Aseprite** inside SpriteDawg.

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
