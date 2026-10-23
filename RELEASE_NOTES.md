Native offline Android Aseprite editor with an adaptive pixel-pocket-and-pencil icon.

- Opening a sprite selects a visible top layer; hidden-layer edits explain the limitation.
- All tools are visible without horizontal scrolling; active tool/layer is shown on the canvas.
- Selecting a tool stops playback so editing is never silently ignored.
- Eraser offers a color-preserving conversion for opaque background layers.
- Pencil, eraser, eyedropper, fill, line/rectangle tools, undo/redo, zoom and pan.
- Layers, animation frames, frame timing, playback, tags, and onion skin.
- RGBA, indexed and grayscale/alpha files; native Kotlin Aseprite codec.
- User data text/JSON and scalar typed properties for game attributes.
- Android Storage Access Framework, PNG export, local recovery; no INTERNET permission.

Android 10 or newer. Open Layers / Frames to choose the layer being edited.

This is a signed, non-debug release APK for Android 10 and newer, including Pixel 8 / GrapheneOS. In Obtainium, add https://github.com/isaiahpettingill/SpriteDawg as a GitHub source. Choose the .apk asset; prereleases are not required.

Version 0.1.2 starts permanent release signing. Android cannot update an earlier development APK signed with another certificate. Save/export your projects, uninstall the development build once, then install this release. Future releases reuse the same certificate and install as updates. Uninstalling removes app-private recovery.

The repository documents supported Aseprite features and safely refused features.
