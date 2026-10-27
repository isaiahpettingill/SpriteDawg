import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'pixel_canvas.dart';
import 'visual_tag_editor.dart';
import 'palette_editor.dart';
import 'engine/palette_presets.dart';
import 'color_picker.dart';
import 'tool_groups.dart';
import 'document_tabs.dart';
import 'linux_updater.dart';
import 'responsive_editor_shell.dart';

void main(List<String> args) {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks([
      'Solarized palette',
    ], solarizedPaletteLicense);
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
      mirrorY = false;
  String gradientDirection = 'vertical';
  int sprayDensity = 12, effectStrength = 50, strokeSeed = 1;
  bool grid = false, onion = false, playing = false, allowExit = false;
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
    'airbrush': (Icons.blur_circular, 'Airbrush'),
    'blur': (Icons.blur_on, 'Blur'),
    'jumble': (Icons.shuffle, 'Jumble'),
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
      final recover = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Recover your drawing?'),
          content: const Text(
            'An unsaved project was found. Open it as a recovered copy, or discard it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Recover'),
            ),
          ],
        ),
      );
      await e.call(recover == true ? 'recover' : 'discardRecovery');
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
    if (state != AppLifecycleState.resumed) stop();
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
    'airbrush': 12,
    'blur': 5,
    'jumble': 5,
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
      case 'exportPng':
        await fileAction('exportPng');
      case 'grid':
        setState(() => grid = !grid);
      case 'onion':
        setState(() => onion = !onion);
      case 'fit':
        setState(() => fitToken++);
      case 'flipHorizontal':
      case 'flipVertical':
        await edit(action);
      case 'metadata':
        await metadata();
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

  Future<void> metadata() async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('User data'),
        children: ['sprite', 'layer', 'cel']
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, s),
                child: Text(
                  s == 'sprite'
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
              icon: const Ic…8499 tokens truncated…lity_off,
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

  Widget framePanel() {
    final frames = e.maps('frames');
    return Material(
      color: const Color(0xff1c2331),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              Text('Frame ${e.frame + 1} / ${frames.length}'),
              const Spacer(),
              IconButton(
                tooltip: 'Add blank frame',
                onPressed: e.busy ? null : () => edit('addFrame'),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Duplicate frame',
                onPressed: e.busy ? null : () => edit('duplicateFrame'),
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                tooltip: 'Delete frame',
                onPressed: e.busy || frames.length < 2
                    ? null
                    : () => edit('deleteFrame'),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              itemCount: frames.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (context, index) => InkWell(
                onTap: e.busy ? null : () => e.call('select', {'frame': index}),
                onLongPress: e.busy
                    ? null
                    : () async {
                        await e.call('select', {'frame': index});
                        await number(
                          'Frame duration (ms)',
                          frames[index]['duration'] as int,
                          1,
                          65535,
                          (n) => edit('frameDuration', {'duration': n}),
                        );
                      },
                child: Container(
                  width: 84,
                  decoration: BoxDecoration(
                    color: index == e.frame
                        ? Theme.of(context).colorScheme.primaryContainer
                        : const Color(0xff293244),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: index == e.frame
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('${frames[index]['duration']} ms'),
                      const SizedBox(height: 4),
                      const Text(
                        'Hold to time',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
