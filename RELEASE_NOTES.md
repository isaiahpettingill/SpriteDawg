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

This first development release uses a CI-generated debug signing key. If replacing
an APK signed by a different key, Android requires uninstalling the old build first;
save/export your projects before uninstalling because app-private recovery is removed.
Configure the documented private signing secrets for stable signed updates.

The repository documents supported Aseprite features and safely refused features.
