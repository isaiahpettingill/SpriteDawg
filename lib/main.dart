import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'pixel_canvas.dart';

void main() => runApp(const PocketPixelApp());

class PocketPixelApp extends StatelessWidget {
  const PocketPixelApp({super.key, this.editor});
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
    home: EditorScreen(editor: editor),
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.editor});
  final Editor? editor;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late final e = widget.editor ?? Editor();
  String tool = 'pencil';
  int color = 0xff000000, brush = 1, fitToken = 0;
  bool grid = false, onion = false, playing = false, allowExit = false;
  String? panel;
  int selectedTag = -1;
  Timer? playback;
  String? lastError;
  static const tools = <String, (IconData, String)>{
    'pencil': (Icons.edit, 'Pencil'),
    'eraser': (Icons.auto_fix_normal, 'Eraser'),
    'fill': (Icons.format_color_fill, 'Fill'),
    'eyedropper': (Icons.colorize, 'Eyedropper'),
    'line': (Icons.show_chart, 'Line'),
    'rectangle': (Icons.crop_square, 'Rectangle'),
    'ellipse': (Icons.circle_outlined, 'Ellipse'),
    'pan': (Icons.pan_tool_alt, 'Pan'),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    e.addListener(update);
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
  }

  void update() {
    if (!mounted) return;
    setState(() {});
    final issue = e.error ?? e.state['recoveryError'] as String?;
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
  }

  @override
  void dispose() {
    playback?.cancel();
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
    if (!e.dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave unsaved work?'),
            content: const Text(
              'Save your drawing before replacing it. Discarding cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard changes'),
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
    if (!await discard()) return;
    if (await e.call('new', {'width': dims[0], 'height': dims[1]}) && mounted) {
      setState(() {
        fitToken++;
        selectedTag = -1;
      });
    }
  }

  Future<void> open() async {
    if (!await discard()) return;
    final old = e.revision;
    await e.call('open');
    if (mounted && e.revision != old) {
      setState(() {
        fitToken++;
        selectedTag = -1;
      });
    }
  }

  Future<void> colorDialog() async {
    var chosen = color;
    final controller = TextEditingController(
      text: chosen.toRadixString(16).padLeft(8, '0').toUpperCase(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Brush color'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 40,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Color(chosen),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'AARRGGBB / RRGGBB',
                    prefixText: '#',
                  ),
                  onChanged: (raw) {
                    final hex = raw.replaceAll('#', '').trim();
                    final n = int.tryParse(hex, radix: 16);
                    if (n != null && (hex.length == 6 || hex.length == 8)) {
                      refresh(
                        () => chosen = hex.length == 6 ? n | 0xff000000 : n,
                      );
                    }
                  },
                ),
                for (final channel in [
                  ('Red', 16),
                  ('Green', 8),
                  ('Blue', 0),
                  ('Alpha', 24),
                ])
                  Row(
                    children: [
                      SizedBox(width: 42, child: Text(channel.$1)),
                      Expanded(
                        child: Slider(
                          value: ((chosen >> channel.$2) & 255).toDouble(),
                          min: 0,
                          max: 255,
                          divisions: 255,
                          onChanged: (v) => refresh(() {
                            chosen =
                                (chosen & ~(255 << channel.$2)) |
                                (v.round() << channel.$2);
                            controller.text = chosen
                                .toRadixString(16)
                                .padLeft(8, '0')
                                .toUpperCase();
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text('${(chosen >> channel.$2) & 255}'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: const Text('Use color'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (result != null && mounted) setState(() => color = result);
  }

  void chooseTool(String value) {
    stop();
    setState(() => tool = value);
  }

  Future<bool> edit(String action, [Map<String, dynamic> args = const {}]) {
    stop();
    return e.edit(action, args);
  }

  Future<void> stroke(String value, List<Offset> points) async {
    stop();
    await e.call('stroke', {
      'tool': value,
      'points': points.map((p) => [p.dx.floor(), p.dy.floor()]).toList(),
      'color': color,
      'size': brush,
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
        await e.call('saveAs');
      case 'exportPng':
        await e.call('exportPng');
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
      case 'help':
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Draw on the go'),
              content: const Text(
                'One finger or stylus draws. Two fingers pan and zoom; adding a second finger cancels the pending stroke.\n\nUse Pan for one-finger navigation, and Fit to recenter. Undo works on complete strokes.\n\nSave keeps the Aseprite layers, frames and metadata. PNG exports only the current frame.\n\nYour work is kept in a private recovery file after each completed edit. No accounts, ads, or internet access.',
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
    final compactHeight = MediaQuery.sizeOf(context).height < 600;
    final hideDrawingStrips = compactHeight && panel != null;
    final layers = e.maps('layers');
    final currentLayer = e.layer < layers.length ? layers[e.layer] : null;
    final layerName = currentLayer == null
        ? 'Layer 1'
        : '${currentLayer['name']}${currentLayer['visible'] == false ? ' (hidden)' : ''}${currentLayer['editable'] == false ? ' (locked)' : ''}';
    final view = PopScope(
      canPop: !e.busy && (allowExit || !e.dirty),
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && e.busy) {
          notice('Wait for the current file operation to finish.');
          return;
        }
        if (!didPop && await discard() && mounted) {
          if (!await e.call('discardRecovery') || !mounted) return;
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
        resizeToAvoidBottomInset: false,
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
                      e.call('save');
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
                  value: 'exportPng',
                  child: Text('Export current frame as PNG'),
                ),
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
                const PopupMenuItem(value: 'help', child: Text('Drawing help')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 3,
                child: e.busy ? const LinearProgressIndicator() : null,
              ),
              if (e.state['recoveryError'] != null)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recovery unavailable: ${e.state['recoveryError']}. Save a copy now.',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: e.busy ? null : () => e.call('saveAs'),
                          child: const Text('Save as'),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tools[tool]!.$2} · $layerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
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
                child: PixelCanvas(
                  editor: e,
                  tool: playing ? 'pan' : tool,
                  color: color,
                  brush: brush,
                  grid: grid,
                  onion: onion,
                  fitToken: fitToken,
                  onPick: (value) => setState(() => color = value),
                  onStroke: stroke,
                ),
              ),
              if (panel != null)
                SizedBox(
                  height: compactHeight
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
              if (!hideDrawingStrips)
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: 'Custom brush color',
                          child: InkWell(
                            onTap: colorDialog,
                            child: Container(
                              width: 40,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(color),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.color_lens_outlined,
                                color: Color(color).computeLuminance() > .5
                                    ? Colors.black
                                    : Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: e.palette.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 5),
                          itemBuilder: (context, index) {
                            final c = e.palette[index];
                            return Center(
                              child: Semantics(
                                label: 'Palette color ${index + 1}',
                                selected: c == color,
                                button: true,
                                child: InkWell(
                                  onTap: () => setState(() => color = c),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Color(c),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: c == color
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.white24,
                                        width: c == color ? 3 : 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Brush size',
                        initialValue: brush,
                        onSelected: (v) => setState(() => brush = v),
                        itemBuilder: (_) => [1, 2, 3, 4, 6, 8, 12, 16]
                            .map(
                              (v) =>
                                  PopupMenuItem(value: v, child: Text('$v px')),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('$brush px'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!hideDrawingStrips)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tools.entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: IconButton.filledTonal(
                              tooltip: entry.value.$2,
                              isSelected: tool == entry.key,
                              onPressed: () => chooseTool(entry.key),
                              style: IconButton.styleFrom(
                                backgroundColor: tool == entry.key
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Colors.transparent,
                              ),
                              icon: Icon(entry.value.$1),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  panelButton('layers', Icons.layers_outlined, 'Layers'),
                  panelButton('frames', Icons.view_carousel_outlined, 'Frames'),
                  panelButton('tags', Icons.sell_outlined, 'Tags'),
                  IconButton(
                    tooltip: playing ? 'Stop animation' : 'Play animation',
                    onPressed: e.maps('frames').length > 1 && !e.busy
                        ? play
                        : null,
                    icon: Icon(
                      playing ? Icons.pause_circle : Icons.play_circle_outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
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
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (e.canRedo && !e.busy) {
            stop();
            e.call('redo');
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!e.busy) {
            stop();
            e.call('save');
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
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
        const SingleActivator(LogicalKeyboardKey.keyH): () => chooseTool('pan'),
      },
      child: Focus(autofocus: true, child: view),
    );
  }

  Widget panelButton(String key, IconData icon, String label) => Expanded(
    child: TextButton(
      onPressed: () {
        stop();
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
              const Text(
                'Layers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
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

  Widget tagPanel() {
    final tags = e.maps('tags');
    return Material(
      color: const Color(0xff1c2331),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Animation tags',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => selectedTag = -1),
                child: const Text('All frames'),
              ),
              IconButton(
                tooltip: 'Add animation tag',
                onPressed: e.busy
                    ? null
                    : () async {
                        final name = await input('Tag name', 'Animation');
                        if (name == null || name.trim().isEmpty) return;
                        final raw = await input(
                          'Tag range',
                          '1–${e.maps('frames').length}',
                          hint: 'First–last frame',
                        );
                        if (raw == null) return;
                        final parts = raw
                            .split(RegExp(r'\s*[-–,]\s*'))
                            .map(int.tryParse)
                            .toList();
                        if (parts.length != 2 ||
                            parts.any((n) => n == null) ||
                            parts[0]! < 1 ||
                            parts[1]! < parts[0]! ||
                            parts[1]! > e.maps('frames').length) {
                          notice('Enter a valid first–last frame range.');
                          return;
                        }
                        await edit('addTag', {
                          'name': name,
                          'from': parts[0]! - 1,
                          'to': parts[1]! - 1,
                          'direction': 0,
                        });
                      },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Expanded(
            child: tags.isEmpty
                ? const Center(child: Text('Add a tag to play a frame range.'))
                : ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final t = tags[index];
                      return ListTile(
                        dense: true,
                        selected: index == selectedTag,
                        title: Text(t['name'] as String),
                        subtitle: Text(
                          'Frames ${(t['from'] as int) + 1}–${(t['to'] as int) + 1}',
                        ),
                        leading: Icon(
                          index == selectedTag
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        onTap: () async {
                          setState(() => selectedTag = index);
                          await e.call('select', {'frame': t['from']});
                        },
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Tag options',
                          onSelected: (value) async {
                            if (value == 'delete') {
                              await edit('deleteTag', {'index': index});
                              if (mounted) setState(() => selectedTag = -1);
                            } else {
                              final text = await input(
                                'Tag user data',
                                t['text'] as String? ?? '',
                                lines: 5,
                              );
                              if (text != null) {
                                await edit('userData', {
                                  'target': 'tag',
                                  'index': index,
                                  'text': text,
                                });
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'data',
                              child: Text('User data'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete tag'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
