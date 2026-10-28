import 'draft_picker.dart';
import 'default_user_data_dialog.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'frame_panel.dart';
import 'export_dialog.dart';
import 'pixel_canvas.dart';
import 'mirroring_controls.dart';
import 'canvas_view_mode.dart';
import 'visual_tag_editor.dart';
import 'palette_editor.dart';
import 'engine/palette_presets.dart';
import 'color_picker.dart';
import 'tool_groups.dart';
import 'document_tabs.dart';
import 'linux_updater.dart'
    if (dart.library.js_interop) 'platform/linux_updater_web.dart';
import 'responsive_editor_shell.dart';

void main(List<String> args) {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks([
      'Solarized palette',
    ], solarizedPaletteLicense);
    yield const LicenseEntryWithLineBreaks([
      'Catppuccin palettes',
    ], catppuccinPaletteLicense);
    yield const LicenseEntryWithLineBreaks([
      'Monokai (Pygments) palette',
    ], pygmentsPaletteLicense);
    yield const LicenseEntryWithLineBreaks([
      'TIC-80 / Sweetie16 palette',
    ], tic80PaletteLicense);
    yield const LicenseEntryWithLineBreaks([
      'DawnBringer 16 palette',
    ], dawnBringerPaletteLicense);
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Image export codecs and dependencies'],
      await rootBundle.loadString(
        'packages/spritedawg_avif_linux/THIRD_PARTY_NOTICES.txt',
      ),
    );
  });
  runApp(PocketPixelApp(initialFiles: args));
}

class PocketPixelApp extends StatelessWidget {
  const PocketPixelApp({super.key, this.editor, this.initialFiles = const []});
  final List<String> initialFiles;
  final Editor? editor;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpriteDawg',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa9b8ff),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff151a25),
    ),
    home: EditorScreen(editor: editor, initialFiles: initialFiles),
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.editor, this.initialFiles = const []});
  final List<String> initialFiles;
  final Editor? editor;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late final e = widget.editor ?? Editor();
  String tool = 'pencil';
  int color = 0xff000000, secondaryColor = 0xffffffff, brush = 1, fitToken = 0;
  int? selectedPaletteIndex;
  bool filledShape = false,
      gradientFill = false,
      mirrorX = false,
      mirrorY = false,
      mirrorDiagonal = false,
      mirrorAntiDiagonal = false;
  String gradientDirection = 'vertical';
  int sprayDensity = 12, effectStrength = 50, strokeSeed = 1;
  bool grid = false, onion = false, playing = false, allowExit = false;
  CanvasViewMode canvasViewMode = CanvasViewMode.normal;
  String? panel;
  bool editingText = false;
  final _tagEditorKey = GlobalKey<VisualTagEditorState>();
  int selectedTag = -1;
  Timer? playback;
  String? lastError;
  static const _externalChannel = MethodChannel('pocketpixel/external');
  final _externalFiles = <String>[];
  bool _initialized = false, _drainingExternal = false, _nativeExternal = false;

  static const tools = <String, (IconData, String)>{
    'pencil': (Icons.edit, 'Pencil'),
    'eraser': (Icons.auto_fix_normal, 'Eraser'),
    'fill': (Icons.format_color_fill, 'Fill'),
    'gradient': (Icons.gradient, 'Gradient'),
    'eyedropper': (Icons.colorize, 'Eyedropper'),
    'line': (Icons.show_chart, 'Line'),
    'rectangle': (Icons.crop_square, 'Rectangle'),
    'ellipse': (Icons.circle_outlined, 'Ellipse'),
    'spray': (Icons.grain, 'Spray'),
    'splatter': (Icons.bubble_chart, 'Splatter'),
    'airbrush': (Icons.blur_circular, 'Airbrush'),
    'blur': (Icons.blur_on, 'Blur'),
    'jumble': (Icons.shuffle, 'Jumble'),
    'metal': (Icons.brightness_medium, 'Metal'),
    'cluster': (Icons.grain, 'Cluster'),
    'stripes': (Icons.texture, 'Stripes'),
    'sphere': (Icons.circle, 'Sphere'),
    'knife': (Icons.architecture, 'Knife'),
    'bark': (Icons.forest, 'Bark'),
    'leaves': (Icons.eco, 'Leaves'),
    'ditherPaint': (Icons.gradient, 'Dither Paint'),
    'ditherRetouch': (Icons.grid_4x4, 'Dither Retouch'),
    'pan': (Icons.pan_tool_alt, 'Pan'),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    e.addListener(update);
    _externalFiles.addAll(widget.initialFiles);
    _externalChannel.setMethodCallHandler((call) async {
      if (call.method == 'files') {
        _externalFiles.addAll((call.arguments as List).cast<String>());
      } else if (call.method == 'pending') {
        _nativeExternal = true;
      }
      _scheduleExternal();
    });
    initialize();
  }

  Future<void> initialize() async {
    await e.call('init');
    if (!mounted) return;
    if (e.state['recoveryAvailable'] == true) {
      await showDraftPicker(context, e);
      if (mounted) setState(() => fitToken++);
    }
    _initialized = true;
    try {
      await _externalChannel.invokeMethod<void>('ready');
    } on MissingPluginException {
      /* Tests and platforms without an external opener. */
    }
    _scheduleExternal();
  }

  void _scheduleExternal() {
    if (!_initialized || _drainingExternal || e.busy || !mounted) return;
    if (!_nativeExternal &&
        _externalFiles.isEmpty &&
        e.state['externalPending'] != true) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openExternal();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _openExternal() async {
    if (_drainingExternal || e.busy || !mounted) return;
    _drainingExternal = true;
    var readyToOpen = false;
    try {
      stop();
      if (!await (_tagEditorKey.currentState?.savePending() ??
          Future.value(true))) {
        return;
      }
      readyToOpen = true;
      do {
        if (_externalFiles.isNotEmpty) {
          final path = _externalFiles.removeAt(0);
          await e.call('openExternal', {'path': path});
        } else {
          _nativeExternal = false;
          await e.call('openExternal');
        }
        if (mounted) {
          setState(() {
            selectedTag = -1;
            fitToken++;
          });
        }
      } while (mounted &&
          (_nativeExternal ||
              _externalFiles.isNotEmpty ||
              e.state['externalPending'] == true));
    } finally {
      _drainingExternal = false;
      if (readyToOpen) _scheduleExternal();
    }
  }

  void update() {
    if (!mounted) return;
    if (selectedPaletteIndex != null &&
        (e.state['depth'] != 8 || selectedPaletteIndex! >= e.palette.length)) {
      selectedPaletteIndex = null;
    }
    if (e.state['depth'] == 8 && selectedPaletteIndex != null) {
      color = e.palette[selectedPaletteIndex!];
    }
    setState(() {});
    final issue =
        e.error ??
        e.state['externalOpenError'] as String? ??
        e.state['recoveryError'] as String?;
    if (issue != null && lastError != issue) {
      lastError = issue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(issue),
              duration: const Duration(seconds: 7),
            ),
          );
        }
      });
    }
    if (issue == null) lastError = null;
    _scheduleExternal();
  }

  @override
  void dispose() {
    playback?.cancel();
    _externalChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    e.removeListener(update);
    e.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      stop();
      unawaited(e.flushDrafts());
    }
  }

  void stop() {
    playback?.cancel();
    if (mounted && playing) setState(() => playing = false);
  }

  Future<bool> discard() async {
    stop();
    if (!await (_tagEditorKey.currentState?.savePending() ??
        Future.value(true))) {
      return false;
    }
    if (!mounted) return false;
    if (!await e.flushDrafts() || !mounted) return false;
    final documents = e.maps('documents');
    final dirtyCount = documents.isEmpty
        ? (e.dirty ? 1 : 0)
        : documents.where((d) => d['dirty'] == true).length;
    if (dirtyCount == 0) return true;
    if (e.state['recoveryError'] != null ||
        documents.any((d) => d['recoveryError'] != null)) {
      notice(
        'Recovery is unavailable for an open drawing. Save your work before leaving.',
      );
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave unsaved work?'),
            content: Text(
              '$dirtyCount open ${dirtyCount == 1 ? 'drawing has' : 'drawings have'} unsaved changes. Recovery copies will be kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave with recovery'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> input(
    String title,
    String value, {
    String? hint,
    TextInputType? keyboard,
    int lines = 1,
  }) async {
    final c = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: lines,
          keyboardType: keyboard,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: lines == 1 ? (v) => Navigator.pop(context, v) : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // The route can animate out after its Future completes; dispose next frame.
    Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
    return result;
  }

  Future<void> number(
    String title,
    int initial,
    int min,
    int max,
    Future<bool> Function(int) apply,
  ) async {
    final raw = await input(
      title,
      '$initial',
      hint: '$min–$max',
      keyboard: TextInputType.number,
    );
    if (raw == null) return;
    final n = int.tryParse(raw);
    if (n == null || n < min || n > max) {
      notice('Enter a number from $min to $max.');
      return;
    }
    await apply(n);
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> newProject() async {
    if (!await beforeDocumentSwitch()) return;
    final raw = await input(
      'New canvas',
      '32 × 32',
      hint: 'Width × height, e.g. 64 × 64',
    );
    if (raw == null) return;
    final dims = raw.split(RegExp(r'\s*[xX×,]\s*')).map(int.tryParse).toList();
    if (dims.length != 2 || dims.any((n) => n == null || n < 1 || n > 2048)) {
      notice('Use dimensions from 1 to 2048, for example 32 × 32.');
      return;
    }
    stop();
    if (await e.call('new', {'width': dims[0], 'height': dims[1]}) && mounted) {
      setState(() {
        fitToken++;
        selectedTag = -1;
      });
    }
  }

  Future<void> open() async {
    if (!await beforeDocumentSwitch()) return;
    final old = e.revision;
    await e.call('open');
    if (mounted && e.revision != old) {
      setState(() {
        fitToken++;
        selectedTag = -1;
      });
    }
  }

  Future<void> colorDialog({bool secondary = false}) async {
    final result = await showSpriteColorPicker(
      context,
      initialColor: secondary ? secondaryColor : color,
      title: secondary ? 'Gradient color' : 'Brush color',
    );
    if (result != null && mounted) {
      setState(() {
        if (secondary) {
          secondaryColor = result;
        } else {
          color = result;
          selectedPaletteIndex = null;
        }
      });
    }
  }

  final _brushSizes = <String, int>{
    'spray': 12,
    'splatter': 20,
    'airbrush': 12,
    'blur': 5,
    'jumble': 5,
    'metal': 12,
    'cluster': 12,
    'stripes': 12,
    'sphere': 12,
    'knife': 12,
    'bark': 12,
    'leaves': 16,
    'ditherPaint': 12,
    'ditherRetouch': 12,
  };
  final _strengths = <String, int>{'airbrush': 20};
  final _groupTools = <String, String>{};
  String get selectedSubtool =>
      (tool == 'rectangle' || tool == 'ellipse') && filledShape
      ? '${tool}Filled'
      : tool;
  List<Widget> groupedTools() => [
    for (final entry in drawingToolGroups.entries)
      DrawingToolGroupButton(
        group: entry.key,
        current: entry.value.any((t) => t.id == selectedSubtool)
            ? selectedSubtool
            : (_groupTools[entry.key] ?? entry.value.first.id),
        active: entry.value.any((t) => t.id == selectedSubtool),
        onSelected: chooseTool,
      ),
  ];
  void chooseTool(String value) {
    stop();
    setState(() {
      _brushSizes[tool] = brush;
      _strengths[tool] = effectStrength;
      for (final entry in drawingToolGroups.entries) {
        if (entry.value.any((t) => t.id == selectedSubtool)) {
          _groupTools[entry.key] = selectedSubtool;
        }
        if (entry.value.any((t) => t.id == value)) {
          _groupTools[entry.key] = value;
        }
      }
      if (value.startsWith('rectangle') || value.startsWith('ellipse')) {
        filledShape = value.endsWith('Filled');
      }
      tool = value.replaceAll('Filled', '');
      brush = _brushSizes[tool] ?? 1;
      effectStrength = _strengths[tool] ?? 50;
    });
  }

  Future<bool> edit(String action, [Map<String, dynamic> args = const {}]) {
    stop();
    return e.edit(action, args);
  }

  Future<void> stroke(String value, List<Offset> points) async {
    stop();
    final seed = strokeSeed;
    strokeSeed = (strokeSeed + 1) & 0xffffffff;
    await e.call('stroke', {
      'tool': value,
      'points': points.map((p) => [p.dx.floor(), p.dy.floor()]).toList(),
      'color': color,
      'size': brush,
      'filled': filledShape,
      'gradient': gradientFill,
      'secondaryColor': secondaryColor,
      'gradientDirection': gradientDirection,
      'density': sprayDensity,
      'strength': effectStrength,
      'seed': seed,
      'mirrorX': mirrorX,
      'mirrorY': mirrorY,
      'mirrorDiagonal': mirrorDiagonal,
      'mirrorAntiDiagonal': mirrorAntiDiagonal,
      if (e.state['depth'] == 8 && selectedPaletteIndex != null)
        'paletteIndex': selectedPaletteIndex,
    });
  }

  int playbackDirection = 1, completedLoops = 0;
  Future<void> play() async {
    if (playing) {
      stop();
      return;
    }
    if (e.maps('frames').length < 2) return;
    setState(() => playing = true);
    final tags = e.maps('tags');
    final tag = selectedTag >= 0 && selectedTag < tags.length
        ? tags[selectedTag]
        : null;
    final direction = tag?['direction'] as int? ?? 0;
    playbackDirection = direction == 1 || direction == 3 ? -1 : 1;
    completedLoops = 0;
    if (tag != null) {
      await e.call('select', {
        'frame': playbackDirection < 0 ? tag['to'] : tag['from'],
      });
    }
    if (mounted && playing) schedule();
  }

  void schedule() {
    if (!playing) return;
    final frames = e.maps('frames');
    if (frames.isEmpty) {
      stop();
      return;
    }
    playback = Timer(
      Duration(
        milliseconds: (frames[e.frame]['duration'] as int)
            .clamp(1, 65535)
            .toInt(),
      ),
      () async {
        if (!mounted || !playing) return;
        final tags = e.maps('tags');
        final tag = selectedTag >= 0 && selectedTag < tags.length
            ? tags[selectedTag]
            : null;
        final from = tag?['from'] as int? ?? 0,
            to = tag?['to'] as int? ?? frames.length - 1,
            direction = tag?['direction'] as int? ?? 0;
        int next = e.frame;
        if (direction == 1) {
          next = e.frame - 1;
          if (next < from || next > to) {
            next = to;
            completedLoops++;
          }
        } else if (direction == 2 || direction == 3) {
          next = e.frame + playbackDirection;
          if (from == to) {
            next = from;
            completedLoops++;
          } else if (next > to) {
            playbackDirection = -1;
            next = to - 1;
            if (direction == 3) completedLoops++;
          } else if (next < from) {
            playbackDirection = 1;
            next = from + 1;
            if (direction == 2) completedLoops++;
          }
        } else {
          next = e.frame + 1;
          if (next > to || next < from) {
            next = from;
            completedLoops++;
          }
        }
        final repeat = tag?['repeat'] as int? ?? 0;
        if (repeat > 0 && completedLoops >= repeat) {
          stop();
          return;
        }
        await e.call('select', {'frame': next});
        if (mounted && playing) schedule();
      },
    );
  }

  Future<void> menu(String action) async {
    stop();
    switch (action) {
      case 'new':
        await newProject();
      case 'open':
        await open();
      case 'saveAs':
        await fileAction('saveAs');
      case 'drafts':
        await showDraftPicker(context, e);
        if (mounted) setState(() => fitToken++);
      case 'exportPng':
        await showExportDialog(context, e);
      case 'grid':
        setState(() => grid = !grid);
      case 'onion':
        setState(() => onion = !onion);
      case 'viewNormal':
        setState(() => canvasViewMode = CanvasViewMode.normal);
      case 'viewTiled':
        setState(() => canvasViewMode = CanvasViewMode.tiled);
      case 'viewSlide':
        setState(() => canvasViewMode = CanvasViewMode.slide);
      case 'fit':
        setState(() => fitToken++);
      case 'flipHorizontal':
      case 'flipVertical':
        await edit(action);
      case 'metadata':
        await metadata();
      case 'defaultUserData':
        await showDefaultUserDataDialog(context, e.defaultsStore);
      case 'updates':
        if (LinuxUpdater.supported && mounted) {
          await showLinuxUpdater(context);
        }
      case 'help':
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Draw on the go'),
              content: const Text(
                'Draw with one finger or a stylus. Pan and zoom with two fingers. Long-hold a toolbar group for subtools. Gradient paints the whole active layer; drag from Start to End.\n\nSave preserves layers, frames and metadata. PNG exports the current frame.\n\nUnsaved edits are kept in recovery copies.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          );
        }
    }
  }

  Future<void> applyDefaultUserData() async {
    final documentId = e.state['documentId'];
    final previous = (e.state['userData'] as Map?)?['sprite'] as String? ?? '';
    try {
      final text = await e.defaultsStore.load();
      if (!mounted) return;
      if (text == previous) return;
      if (text.isEmpty || previous.isNotEmpty) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              text.isEmpty
                  ? 'Clear project user data?'
                  : 'Replace project user data?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(text.isEmpty ? 'Clear' : 'Replace'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      if (documentId != e.state['documentId'] ||
          previous !=
              ((e.state['userData'] as Map?)?['sprite'] as String? ?? '')) {
        throw StateError('Project changed. Try applying defaults again.');
      }
      await edit('userData', {'target': 'sprite', 'text': text});
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$failure')));
      }
    }
  }

  Future<void> metadata() async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('User data'),
        children: ['sprite', 'layer', 'cel', 'applyDefaults']
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, s),
                child: Text(
                  s == 'applyDefaults'
                      ? 'Apply defaults to project'
                      : s == 'sprite'
                      ? 'Project'
                      : s == 'layer'
                      ? 'Active layer'
                      : 'Active cel',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;
    if (target == 'applyDefaults') {
      await applyDefaultUserData();
      return;
    }
    final data = e.state['userData'] as Map?;
    final value = await input(
      '$target user data',
      data?[target] as String? ?? '',
      lines: 5,
      hint: 'Text or JSON; other metadata is preserved',
    );
    if (value != null) {
      await edit('userData', {'target': target, 'text': value});
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactHeight =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        600;
    final tightHeight =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        430;
    final compactTags = panel == 'tags' && compactHeight;
    final hideDrawingStrips =
        (compactHeight && panel != null) || panel == 'tags';
    final layers = e.maps('layers');
    final currentLayer = e.layer < layers.length ? layers[e.layer] : null;
    final layerName = currentLayer == null
        ? 'Layer 1'
        : '${currentLayer['name']}${currentLayer['visible'] == false ? ' (hidden)' : ''}${currentLayer['editable'] == false ? ' (locked)' : ''}';
    final view = PopScope(
      canPop: !e.busy && allowExit,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && e.busy) {
          notice('Wait for the current file operation to finish.');
          return;
        }
        if (!didPop && await discard() && mounted) {
          setState(() => allowExit = true);
          await WidgetsBinding.instance.endOfFrame;
          if (!context.mounted) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            await SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: panel == 'tags',
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpriteDawg${e.dirty ? ' •' : ''}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${e.width} × ${e.height} · ${e.state['depth'] ?? 32}-bit',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Open Aseprite',
              onPressed: e.busy ? null : open,
              icon: const Icon(Icons.folder_open),
            ),
            IconButton(
              tooltip: 'Save Aseprite',
              onPressed: e.busy
                  ? null
                  : () {
                      stop();
                      fileAction('save');
                    },
              icon: const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Project and view options',
              enabled: !e.busy,
              onSelected: menu,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'new', child: Text('New canvas')),
                const PopupMenuItem(value: 'saveAs', child: Text('Save as…')),
                const PopupMenuItem(
                  value: 'drafts',
                  child: Text('Internal drafts…'),
                ),
                const PopupMenuItem(value: 'exportPng', child: Text('Export…')),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'grid',
                  checked: grid,
                  child: const Text('Pixel grid'),
                ),
                CheckedPopupMenuItem(
                  value: 'onion',
                  checked: onion,
                  child: const Text('Onion skin'),
                ),
                CheckedPopupMenuItem(
                  value: 'viewNormal',
                  checked: canvasViewMode == CanvasViewMode.normal,
                  child: const Text('View · Normal'),
                ),
                CheckedPopupMenuItem(
                  value: 'viewTiled',
                  checked: canvasViewMode == CanvasViewMode.tiled,
                  child: const Text('View · Tiled (3×3)'),
                ),
                CheckedPopupMenuItem(
                  value: 'viewSlide',
                  checked: canvasViewMode == CanvasViewMode.slide,
                  child: const Text('View · Slide'),
                ),
                const PopupMenuItem(value: 'fit', child: Text('Fit canvas')),
                const PopupMenuItem(
                  value: 'flipHorizontal',
                  child: Text('Flip active cel horizontally'),
                ),
                const PopupMenuItem(
                  value: 'flipVertical',
                  child: Text('Flip active cel vertically'),
                ),
                const PopupMenuItem(
                  value: 'metadata',
                  child: Text('User data'),
                ),
                const PopupMenuItem(
                  value: 'defaultUserData',
                  child: Text('Default user data'),
                ),
                const PopupMenuItem(value: 'help', child: Text('Drawing help')),
                if (LinuxUpdater.supported)
                  const PopupMenuItem(
                    value: 'updates',
                    child: Text('Check for updates…'),
                  ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (recoveryIssue != null) recoveryBanner(),
              Expanded(
                child: ResponsiveEditorShell(
                  documentTabs: DocumentTabs(
                    editor: e,
                    onNew: () => newProject(),
                    onOpen: () => open(),
                    beforeSwitch: beforeDocumentSwitch,
                  ),
                  canvas: Column(
                    children: [
                      paletteStrip(),
                      if (hasStrokeOptions) strokeOptions(),
                      Expanded(child: drawingCanvas()),
                    ],
                  ),
                  tools: toolRail(),
                  layers: layerPanel(),
                  timeline: wideTimeline(),
                  timelineHeight: panel == 'tags' ? 260 : 168,
                  mobileBody: Column(
                    children: [
                      SizedBox(
                        height: 3,
                        child: e.busy ? const LinearProgressIndicator() : null,
                      ),
                      if (!compactTags)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tool == 'gradient'
                                      ? 'Gradient · whole active layer'
                                      : '${tools[tool]!.$2} · $layerName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ),
                              if (tightHeight)
                                IconButton(
                                  tooltip: 'Manage palette and color mode',
                                  onPressed: managePalette,
                                  icon: const Icon(Icons.palette_outlined),
                                ),
                              if (tightHeight) mirroringMenu(),
                              if (tightHeight) compactBrushMenu(),
                              IconButton(
                                tooltip: 'Undo',
                                onPressed: e.canUndo && !e.busy
                                    ? () {
                                        stop();
                                        e.call('undo');
                                      }
                                    : null,
                                icon: const Icon(Icons.undo),
                              ),
                              IconButton(
                                tooltip: 'Redo',
                                onPressed: e.canRedo && !e.busy
                                    ? () {
                                        stop();
                                        e.call('redo');
                                      }
                                    : null,
                                icon: const Icon(Icons.redo),
                              ),
                              IconButton(
                                tooltip: 'Fit canvas',
                                onPressed: () => setState(() => fitToken++),
                                icon: const Icon(Icons.fit_screen),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: compactTags ? tagPanel() : drawingCanvas(),
                      ),
                      if (panel != null && !compactTags)
                        SizedBox(
                          height: panel == 'frames'
                              ? 120
                              : panel == 'tags'
                              ? 280
                              : compactHeight
                              ? (MediaQuery.sizeOf(context).height - 210)
                                    .clamp(130.0, 180.0)
                                    .toDouble()
                              : 180,
                          child: panel == 'layers'
                              ? layerPanel()
                              : panel == 'frames'
                              ? framePanel()
                              : tagPanel(),
                        ),
                      if (!hideDrawingStrips && !tightHeight) paletteStrip(),
                      if (!hideDrawingStrips && !tightHeight && hasStrokeOptions)
                        strokeOptions(),
                      if (!hideDrawingStrips)
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: groupedTools(),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          panelButton(
                            'layers',
                            Icons.layers_outlined,
                            'Layers',
                          ),
                          panelButton(
                            'frames',
                            Icons.view_carousel_outlined,
                            'Frames',
                          ),
                          panelButton('tags', Icons.sell_outlined, 'Tags'),
                          IconButton(
                            iconSize: 32,
                            constraints: const BoxConstraints(
                              minWidth: 56,
                              minHeight: 48,
                            ),
                            tooltip: playing
                                ? 'Stop animation'
                                : 'Play animation',
                            onPressed: e.maps('frames').length > 1 && !e.busy
                                ? play
                                : null,
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle
                                  : Icons.play_circle_outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: editingText
          ? const <ShortcutActivator, VoidCallback>{}
          : {
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
              ): () {
                if (e.canUndo && !e.busy) {
                  stop();
                  e.call('undo');
                }
              },
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): () {
                if (e.canRedo && !e.busy) {
                  stop();
                  e.call('redo');
                }
              },
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () {
                if (e.canRedo && !e.busy) {
                  stop();
                  e.call('redo');
                }
              },
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                if (!e.busy) {
                  stop();
                  fileAction('save');
                }
              },
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                if (!e.busy) open();
              },
              const SingleActivator(LogicalKeyboardKey.keyB): () =>
                  chooseTool('pencil'),
              const SingleActivator(LogicalKeyboardKey.keyE): () =>
                  chooseTool('eraser'),
              const SingleActivator(LogicalKeyboardKey.keyG): () =>
                  chooseTool('fill'),
              const SingleActivator(LogicalKeyboardKey.keyI): () =>
                  chooseTool('eyedropper'),
              const SingleActivator(LogicalKeyboardKey.keyH): () =>
                  chooseTool('pan'),
            },
      child: Focus(autofocus: true, child: view),
    );
  }

  Future<bool> fileAction(String method) async {
    stop();
    if (!await (_tagEditorKey.currentState?.savePending() ??
        Future.value(true))) {
      return false;
    }
    return e.call(method);
  }

  String? get recoveryIssue {
    final active = e.state['recoveryError'] as String?;
    if (active != null) return active;
    for (final doc in e.maps('documents')) {
      if (doc['recoveryError'] != null) {
        return '${doc['title']}: ${doc['recoveryError']}';
      }
    }
    return null;
  }

  Widget recoveryBanner() {
    final problem = e
        .maps('documents')
        .where((d) => d['recoveryError'] != null && d['active'] != true)
        .firstOrNull;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recovery unavailable: $recoveryIssue. Save a copy now.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: e.busy
                  ? null
                  : () async {
                      if (problem != null) {
                        if (await beforeDocumentSwitch()) {
                          await e.call('selectDocument', {'id': problem['id']});
                        }
                      } else {
                        await fileAction('saveAs');
                      }
                    },
              child: Text(problem == null ? 'Save as' : 'Open drawing'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> beforeDocumentSwitch() async {
    stop();
    if (!await (_tagEditorKey.currentState?.savePending() ??
        Future.value(true))) {
      return false;
    }
    if (!mounted) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectedTag = -1;
      selectedPaletteIndex = null;
      fitToken++;
    });
    return true;
  }

  Future<void> managePalette() async {
    stop();
    await showPaletteEditor(
      context,
      editor: e,
      currentColor: () => color,
      currentPaletteIndex: () => selectedPaletteIndex,
      onSelect: (value, index) {
        setState(() {
          color = value;
          selectedPaletteIndex = index;
        });
      },
    );
  }

  Widget drawingCanvas() => PixelCanvas(
    key: const Key('drawing-workspace'),
    editor: e,
    tool: playing ? 'pan' : tool,
    color: color,
    brush: brush,
    grid: grid,
    onion: onion,
    viewMode: canvasViewMode,
    fitToken: fitToken,
    filled: filledShape,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mirrorDiagonal: mirrorDiagonal,
    mirrorAntiDiagonal: mirrorAntiDiagonal,
    density: sprayDensity,
    seed: strokeSeed,
    strength: effectStrength,
    previewOptions: {
      'secondaryColor': secondaryColor,
      if (e.state['depth'] == 8 && selectedPaletteIndex != null)
        'paletteIndex': selectedPaletteIndex,
    },
    onPick: (value) => setState(() {
      color = value;
      selectedPaletteIndex = null;
    }),
    onStroke: stroke,
  );
  Widget mirroringMenu() => MirroringButton(
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mirrorDiagonal: mirrorDiagonal,
    mirrorAntiDiagonal: mirrorAntiDiagonal,
    ignored: tool == 'gradient',
    onToggle: (value) => setState(() {
      switch (value) {
        case 'x':
          mirrorX = !mirrorX;
        case 'y':
          mirrorY = !mirrorY;
        case 'diagonal':
          mirrorDiagonal = !mirrorDiagonal;
        case 'antiDiagonal':
          mirrorAntiDiagonal = !mirrorAntiDiagonal;
        case 'off':
          mirrorX = mirrorY = mirrorDiagonal = mirrorAntiDiagonal = false;
      }
    }),
  );

  // The former mirror-checkbox row now holds a second row of palette colors.
  // Both responsive layouts share this strip, including exact-index selection.
  Widget paletteStrip() => SizedBox(
    key: const Key('palette-strip'),
    height: 96,
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Column(
            children: [
              IconButton(
                tooltip: 'Brush color',
                onPressed: colorDialog,
                icon: BrushColorSwatch(color: color),
              ),
              IconButton(
                tooltip: 'Manage palette and color mode',
                onPressed: e.busy ? null : managePalette,
                icon: const Icon(Icons.palette_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            key: const Key('palette-swatches'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 44,
            ),
            itemCount: e.palette.length,
            itemBuilder: (context, index) {
              final c = e.palette[index];
              final selected = e.state['depth'] == 8 && selectedPaletteIndex != null
                  ? index == selectedPaletteIndex
                  : c == color;
              return Semantics(
                label: 'Palette color ${index + 1}',
                selected: selected,
                button: true,
                child: InkWell(
                  key: Key('palette-color-$index'),
                  onTap: () => setState(() {
                    color = c;
                    selectedPaletteIndex = index;
                  }),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: BrushColorSwatch(color: c, size: 30),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 48,
          child: Column(children: [mirroringMenu(), compactBrushMenu()]),
        ),
      ],
    ),
  );

  bool get hasStrokeOptions => const {
    'rectangle', 'ellipse', 'fill', 'gradient', 'spray', 'blur', 'jumble',
    'airbrush', 'ditherPaint',
  }.contains(tool);

  Widget compactBrushMenu() => PopupMenuButton<String>(
    tooltip: 'Brush options',
    icon: const Icon(Icons.tune),
    onSelected: (value) async {
      switch (value) {
        case 'size':
          await number('Brush size', brush, 1, 32, (n) async {
            setState(() => brush = n);
            return true;
          });
        case 'filled':
          setState(() => filledShape = !filledShape);
        case 'gradient':
          setState(() => gradientFill = !gradientFill);
        case 'primary':
          await colorDialog();
        case 'secondary':
          await colorDialog(secondary: true);
        case 'axis':
          setState(
            () => gradientDirection = gradientDirection == 'vertical'
                ? 'horizontal'
                : 'vertical',
          );
        case 'density':
          await number('Spray particles per stamp', sprayDensity, 1, 100, (
            n,
          ) async {
            setState(() => sprayDensity = n);
            return true;
          });
        case 'strength':
          await number('Effect strength', effectStrength, 1, 100, (n) async {
            setState(() => effectStrength = n);
            return true;
          });
      }
    },
    itemBuilder: (_) => [
      if (tool != 'gradient')
        PopupMenuItem(value: 'size', child: Text('Brush size: $brush px')),
      if (tool == 'rectangle' || tool == 'ellipse')
        CheckedPopupMenuItem(
          value: 'filled',
          checked: filledShape,
          child: const Text('Filled shape'),
        ),
      if (tool == 'fill')
        CheckedPopupMenuItem(
          value: 'gradient',
          checked: gradientFill,
          child: const Text('Gradient fill'),
        ),
      if (tool == 'gradient')
        const PopupMenuItem(value: 'primary', child: Text('Start color')),
      if (tool == 'gradient' || (tool == 'fill' && gradientFill)) ...[
        const PopupMenuItem(
          value: 'secondary',
          child: Text('Second gradient color'),
        ),
        if (tool == 'fill')
          PopupMenuItem(
            value: 'axis',
            child: Text('Gradient: $gradientDirection'),
          ),
      ],
      if (tool == 'spray')
        PopupMenuItem(
          value: 'density',
          child: Text('Spray density: $sprayDensity'),
        ),
      if (tool == 'blur' ||
          tool == 'jumble' ||
          tool == 'airbrush' ||
          tool == 'ditherPaint')
        PopupMenuItem(
          value: 'strength',
          child: Text('Strength: $effectStrength%'),
        ),
    ],
  );

  Widget strokeOptions() => SizedBox(
    height: 48,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (tool == 'rectangle' || tool == 'ellipse')
            TextButton.icon(
              onPressed: () => setState(() => filledShape = !filledShape),
              icon: Icon(filledShape ? Icons.square : Icons.crop_square),
              label: Text(filledShape ? 'Filled' : 'Outline'),
            ),
          if (tool == 'fill')
            TextButton.icon(
              onPressed: () => setState(() => gradientFill = !gradientFill),
              icon: Icon(
                gradientFill ? Icons.gradient : Icons.format_color_fill,
              ),
              label: Text(gradientFill ? 'Gradient' : 'Solid fill'),
            ),
          if (tool == 'gradient')
            TextButton.icon(
              onPressed: colorDialog,
              icon: BrushColorSwatch(color: color),
              label: const Text('Start'),
            ),
          if (tool == 'gradient' || (tool == 'fill' && gradientFill)) ...[
            TextButton.icon(
              onPressed: () => colorDialog(secondary: true),
              icon: BrushColorSwatch(color: secondaryColor),
              label: Text(tool == 'gradient' ? 'End' : 'Second color'),
            ),
            if (tool == 'fill')
              TextButton.icon(
                onPressed: () => setState(
                  () => gradientDirection = gradientDirection == 'vertical'
                      ? 'horizontal'
                      : 'vertical',
                ),
                icon: Icon(
                  gradientDirection == 'vertical' ? Icons.south : Icons.east,
                ),
                label: Text(
                  gradientDirection == 'vertical' ? 'Vertical' : 'Horizontal',
                ),
              ),
          ],
          if (tool == 'gradient')
            IconButton(
              tooltip: 'Swap gradient colors',
              onPressed: () => setState(() {
                final old = color;
                color = secondaryColor;
                secondaryColor = old;
                selectedPaletteIndex = null;
              }),
              icon: const Icon(Icons.swap_horiz),
            ),
          if (tool == 'spray')
            PopupMenuButton<int>(
              tooltip: 'Spray density',
              onSelected: (value) => setState(() => sprayDensity = value),
              itemBuilder: (_) => [1, 4, 8, 12, 24, 50, 100]
                  .map(
                    (v) => PopupMenuItem(
                      value: v,
                      child: Text('$v particles per stamp'),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Density $sprayDensity'),
              ),
            ),
          if (tool == 'blur' ||
              tool == 'jumble' ||
              tool == 'airbrush' ||
              tool == 'ditherPaint')
            PopupMenuButton<int>(
              tooltip: 'Effect strength',
              onSelected: (value) => setState(() => effectStrength = value),
              itemBuilder: (_) => [10, 25, 50, 75, 100]
                  .map((v) => PopupMenuItem(value: v, child: Text('$v%')))
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Strength $effectStrength%'),
              ),
            ),
        ],
      ),
    ),
  );
  Widget toolRail() => Column(
    children: [
      ...groupedTools(),
      const Divider(),
      IconButton(
        tooltip: 'Undo',
        onPressed: e.canUndo && !e.busy ? () => e.call('undo') : null,
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        tooltip: 'Redo',
        onPressed: e.canRedo && !e.busy ? () => e.call('redo') : null,
        icon: const Icon(Icons.redo),
      ),
    ],
  );
  Widget wideTimeline() => Column(
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            TextButton(
              onPressed: () => setState(() => panel = 'frames'),
              child: const Text('Frames'),
            ),
            TextButton(
              onPressed: () => setState(() => panel = 'tags'),
              child: const Text('Tags'),
            ),
            const Spacer(),
            IconButton(
              iconSize: 32,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: playing ? 'Stop animation' : 'Play animation',
              onPressed: e.maps('frames').length > 1 ? play : null,
              icon: Icon(
                playing ? Icons.pause_circle : Icons.play_circle_outline,
              ),
            ),
          ],
        ),
      ),
      Expanded(child: panel == 'tags' ? tagPanel() : framePanel()),
    ],
  );

  Widget panelButton(String key, IconData icon, String label) => Expanded(
    child: TextButton(
      onPressed: () {
        stop();
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => panel = panel == key ? null : key);
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: const Size(0, 48),
        foregroundColor: panel == key
            ? Theme.of(context).colorScheme.primary
            : Colors.white70,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
  Widget layerPanel() {
    final layers = e.maps('layers');
    return Material(
      color: const Color(0xff1c2331),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Layers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Add layer',
                onPressed: e.busy
                    ? null
                    : () async {
                        final name = await input(
                          'New layer',
                          'Layer ${layers.length + 1}',
                        );
                        if (name != null && name.trim().isNotEmpty) {
                          await edit('addLayer', {'name': name});
                        }
                      },
                icon: const Icon(Icons.add),
              ),
              PopupMenuButton<String>(
                tooltip: 'Active layer options',
                enabled: !e.busy,
                onSelected: (value) async {
                  switch (value) {
                    case 'rename':
                      final name = await input(
                        'Rename layer',
                        layers[e.layer]['name'] as String,
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await edit('renameLayer', {'name': name});
                      }
                    case 'opacity':
                      await number(
                        'Layer opacity (0–255)',
                        layers[e.layer]['opacity'] as int,
                        0,
                        255,
                        (n) => edit('layerOpacity', {'opacity': n}),
                      );
                    case 'up':
                      if (e.layer < layers.length - 1) {
                        await edit('moveLayer', {'to': e.layer + 1});
                      }
                    case 'down':
                      if (e.layer > 0) {
                        await edit('moveLayer', {'to': e.layer - 1});
                      }
                    case 'transparent':
                      await edit('transparentLayer');
                    case 'delete':
                      if (layers.length > 1) await edit('deleteLayer');
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'opacity', child: Text('Opacity')),
                  PopupMenuItem(
                    value: 'up',
                    enabled: e.layer < layers.length - 1,
                    child: const Text('Move up'),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: e.layer > 0,
                    child: const Text('Move down'),
                  ),
                  const PopupMenuItem(
                    value: 'transparent',
                    child: Text('Allow transparency'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: layers.length > 1,
                    child: const Text('Delete layer'),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: layers.length,
              itemBuilder: (context, n) {
                final index = layers.length - 1 - n, l = layers[index];
                return SizedBox(
                  height: 48,
                  child: ListTile(
                    dense: true,
                    selected: index == e.layer,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .4),
                    leading: IconButton(
                      tooltip: l['visible'] == true
                          ? 'Hide layer'
                          : 'Show layer',
                      onPressed: e.busy
                          ? null
                          : () async {
                              await e.call('select', {'layer': index});
                              await edit('layerVisibility', {
                                'visible': l['visible'] != true,
                              });
                            },
                      icon: Icon(
                        l['visible'] == true
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                    title: Text(l['name'] as String, maxLines: 1),
                    trailing: Text(
                      '${((l['opacity'] as int) * 100 / 255).round()}%',
                    ),
                    onTap: e.busy
                        ? null
                        : () => e.call('select', {'layer': index}),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget framePanel() => FramePanel(
    frame: e.frame,
    durations: [for (final frame in e.maps('frames')) frame['duration'] as int],
    documentId: e.state['documentId'],
    busy: e.busy,
    onSelect: (index) => e.call('select', {'frame': index}),
    onDuration: frameDuration,
    onAdd: () => edit('addFrame'),
    onDuplicate: () => edit('duplicateFrame'),
    onDelete: () => edit('deleteFrame'),
  );

  Future<void> frameDuration(int index) async {
    if (e.busy) return;
    stop();
    if (!await e.call('select', {'frame': index}) || !mounted) return;
    final frames = e.maps('frames');
    if (index >= frames.length) return;
    await number(
      'Frame duration (ms)',
      frames[index]['duration'] as int,
      1,
      65535,
      (n) => edit('frameDuration', {'duration': n}),
    );
  }

  Widget tagPanel() => VisualTagEditor(
    key: _tagEditorKey,
    editor: e,
    selectedTag: selectedTag,
    playing: playing,
    onSelected: (index) => setState(() => selectedTag = index),
    onEdit: edit,
    onStop: stop,
    onPlay: () => play(),
    onEditingChanged: (value) {
      if (mounted) setState(() => editingText = value);
    },
    onData: (index) async {
      final tags = e.maps('tags');
      if (index < 0 || index >= tags.length) return;
      final text = await input(
        'Tag user data',
        tags[index]['text'] as String? ?? '',
        lines: 5,
      );
      if (text != null) {
        await edit('userData', {'target': 'tag', 'index': index, 'text': text});
      }
    },
  );
}
