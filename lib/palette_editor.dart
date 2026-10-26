import 'package:flutter/material.dart';

import 'editor.dart';
import 'color_picker.dart';

Future<void> showPaletteEditor(
  BuildContext context, {
  required Editor editor,
  int Function()? currentColor,
  int? Function()? currentPaletteIndex,
  required void Function(int color, int index) onSelect,
}) => showDialog<void>(
  context: context,
  builder: (_) => PaletteEditor(
    editor: editor,
    onSelect: onSelect,
    currentColor: currentColor,
    currentPaletteIndex: currentPaletteIndex,
  ),
);

/// Palette changes are document edits, not application-global preferences.
class PaletteEditor extends StatefulWidget {
  const PaletteEditor({
    super.key,
    required this.editor,
    required this.onSelect,
    this.currentColor,
    this.currentPaletteIndex,
  });
  final Editor editor;
  final int Function()? currentColor;
  final int? Function()? currentPaletteIndex;
  final void Function(int color, int index) onSelect;
  @override
  State<PaletteEditor> createState() => _PaletteEditorState();
}

class _PaletteEditorState extends State<PaletteEditor> {
  final name = TextEditingController();
  int selected = 0;
  String? message;
  Editor get e => widget.editor;
  @override
  void initState() {
    super.initState();
    _load();
    e.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    e.removeListener(_changed);
    name.dispose();
    super.dispose();
  }

  void _load() {
    final colors = e.palette;
    selected = selected.clamp(0, colors.isEmpty ? 0 : colors.length - 1);
    final names = e.state['paletteNames'];
    name.text = names is List && selected < names.length
        ? '${names[selected] ?? ''}'
        : '';
  }

  Future<bool> _edit(String action, Map<String, dynamic> args) async {
    final ok = await e.edit(action, args);
    if (!mounted) return ok;
    setState(() {
      message = ok ? null : e.error;
      if (ok) {
        if (action == 'paletteMove') selected = args['to'] as int;
        if (action == 'paletteAdd') selected = e.palette.length - 1;
        if (action == 'paletteRemove') {
          final replacement = args['replacement'] as int;
          selected = replacement > (args['index'] as int)
              ? replacement - 1
              : replacement;
        }
        _load();
      }
    });
    if (ok && e.palette.isNotEmpty) {
      widget.onSelect(e.palette[selected], selected);
    }
    return ok;
  }

  Future<void> _addCurrentColor() async {
    if (e.busy) return;
    final color = widget.currentColor!();
    final explicit = widget.currentPaletteIndex?.call();
    var existing = -1;
    if (explicit != null &&
        explicit >= 0 &&
        explicit < e.palette.length &&
        e.palette[explicit] == color) {
      existing = explicit;
    } else {
      for (var i = 0; i < e.palette.length; i++) {
        // An opaque color must not accidentally select the transparent index.
        if (e.palette[i] == color &&
            !(e.state['depth'] == 8 &&
                i == e.state['transparentIndex'] &&
                color >> 24 != 0)) {
          existing = i;
          break;
        }
      }
    }
    if (existing >= 0) {
      setState(() {
        selected = existing;
        _load();
        message = 'Already in palette · swatch ${existing + 1} selected';
      });
      widget.onSelect(color, existing);
      return;
    }
    if (await _edit('paletteAdd', {'color': color, 'name': ''}) && mounted) {
      setState(() => message = 'Current color added');
    }
  }

  Future<void> _remove() async {
    int? replacement;
    final answer = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Remove swatch?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Replace this swatch in every frame. Pixel colors may change.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Replacement swatch',
                ),
                items: [
                  for (var i = 0; i < e.palette.length; i++)
                    if (i != selected)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          'Swatch ${i + 1} · #${e.palette[i].toRadixString(16).padLeft(8, '0')}',
                        ),
                      ),
                ],
                onChanged: (value) => update(() => replacement = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: replacement == null
                  ? null
                  : () => Navigator.pop(context, replacement),
              child: const Text('Remap and remove'),
            ),
          ],
        ),
      ),
    );
    if (answer != null) {
      await _edit('paletteRemove', {'index': selected, 'replacement': answer});
    }
  }

  Future<void> _convert() async {
    final indexed = e.state['depth'] == 8;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(indexed ? 'Convert to RGBA?' : 'Convert to indexed?'),
        content: Text(
          indexed
              ? 'Keep the appearance, but replace palette indices with RGBA colors.'
              : 'Convert every frame to its palette. Colors and transparency may change. Keep an original copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _edit('convertMode', {'depth': indexed ? 32 : 8});
    }
  }

  Future<void> _history(String method) async {
    final ok = await e.call(method);
    if (!mounted) return;
    setState(() {
      message = ok ? null : e.error;
      _load();
    });
    if (ok && e.palette.isNotEmpty) {
      widget.onSelect(e.palette[selected], selected);
    }
  }

  Future<void> _chooseColor({bool add = false}) async {
    final chosen = await showSpriteColorPicker(
      context,
      initialColor: add
          ? (widget.currentColor?.call() ?? 0xff000000)
          : e.palette[selected],
      title: add ? 'New swatch' : 'Edit swatch ${selected + 1}',
    );
    if (chosen == null || !mounted) return;
    await _edit(add ? 'paletteAdd' : 'paletteEdit', {
      if (!add) 'index': selected,
      'color': chosen,
      'name': add ? '' : name.text,
    });
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: name.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Name swatch ${selected + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name (optional)'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dialog exit animation can still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (result != null && mounted) {
      await _edit('paletteEdit', {
        'index': selected,
        'color': e.palette[selected],
        'name': result,
      });
    }
  }

  Future<void> _more(String action) async {
    if (e.busy) return;
    switch (action) {
      case 'rename':
        await _rename();
      case 'add':
        await _chooseColor(add: true);
      case 'earlier':
        await _edit('paletteMove', {'index': selected, 'to': selected - 1});
      case 'later':
        await _edit('paletteMove', {'index': selected, 'to': selected + 1});
      case 'remove':
        await _remove();
      case 'convert':
        await _convert();
      case 'undo':
        await _history('undo');
      case 'redo':
        await _history('redo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = e.palette;
    final indexed = e.state['depth'] == 8;
    final mode = indexed
        ? 'Indexed'
        : e.state['depth'] == 16
        ? 'Grayscale'
        : 'RGBA';
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        key: const Key('palette-content'),
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Palette · $mode',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Palette options',
                    enabled: !e.busy,
                    onSelected: _more,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'add',
                        child: Text('New custom swatch…'),
                      ),
                      PopupMenuItem(
                        value: 'rename',
                        enabled: colors.isNotEmpty,
                        child: const Text('Name selected swatch…'),
                      ),
                      PopupMenuItem(
                        value: 'earlier',
                        enabled: selected > 0,
                        child: const Text('Move selected earlier'),
                      ),
                      PopupMenuItem(
                        value: 'later',
                        enabled: selected < colors.length - 1,
                        child: const Text('Move selected later'),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        enabled: colors.length > 1,
                        child: const Text('Remove selected…'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'convert',
                        child: Text(
                          indexed ? 'Convert to RGBA…' : 'Convert to indexed…',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'undo',
                        enabled: e.canUndo,
                        child: const Text('Undo'),
                      ),
                      PopupMenuItem(
                        value: 'redo',
                        enabled: e.canRedo,
                        child: const Text('Redo'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Close palette',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.currentColor != null) ...[
                      FilledButton.tonalIcon(
                        key: const Key('add-current-color'),
                        onPressed: e.busy ? null : _addCurrentColor,
                        icon: const Icon(Icons.add),
                        label: const Text('Add current color'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(message!),
                        ),
                      ),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < colors.length; i++)
                          Semantics(
                            label:
                                'Swatch ${i + 1}${indexed && i == e.state['transparentIndex'] ? ', transparent index' : ''}',
                            selected: selected == i,
                            button: true,
                            child: Tooltip(
                              message:
                                  'Swatch ${i + 1} · #${colors[i].toRadixString(16).padLeft(8, '0')}',
                              child: InkWell(
                                onTap: e.busy
                                    ? null
                                    : () {
                                        setState(() {
                                          selected = i;
                                          _load();
                                          message = null;
                                        });
                                        widget.onSelect(colors[i], i);
                                      },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: selected == i
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: BrushColorSwatch(color: colors[i]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (colors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Swatch ${selected + 1}${name.text.isEmpty ? '' : ' · ${name.text}'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (indexed && selected == e.state['transparentIndex'])
                        const Text('Transparent index'),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: e.busy ? null : _chooseColor,
                        icon: const Icon(Icons.tune),
                        label: const Text('Edit selected color'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
