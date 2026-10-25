import 'package:flutter/material.dart';
import 'editor.dart';

Future<void> showPaletteEditor(
  BuildContext context, {
  required Editor editor,
  required void Function(int color, int index) onSelect,
}) => showDialog<void>(
  context: context,
  builder: (_) => PaletteEditor(editor: editor, onSelect: onSelect),
);

/// Palette changes are document edits, not application-global preferences.
class PaletteEditor extends StatefulWidget {
  const PaletteEditor({
    super.key,
    required this.editor,
    required this.onSelect,
  });
  final Editor editor;
  final void Function(int color, int index) onSelect;
  @override
  State<PaletteEditor> createState() => _PaletteEditorState();
}

class _PaletteEditorState extends State<PaletteEditor> {
  final hex = TextEditingController();
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
    hex.dispose();
    name.dispose();
    super.dispose();
  }

  void _load() {
    final colors = e.palette;
    selected = selected.clamp(0, colors.isEmpty ? 0 : colors.length - 1);
    hex.text = colors.isEmpty
        ? 'FF000000'
        : colors[selected].toRadixString(16).padLeft(8, '0').toUpperCase();
    final names = e.state['paletteNames'];
    name.text = names is List && selected < names.length
        ? '${names[selected] ?? ''}'
        : '';
  }

  int? _color() {
    final value = hex.text.trim().replaceFirst('#', '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
      setState(
        () => message = 'Enter RRGGBB or AARRGGBB, for example FF44AA88.',
      );
      return null;
    }
    return int.parse(value.length == 6 ? 'FF$value' : value, radix: 16);
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

  Future<void> _remove() async {
    int? replacement;
    final answer = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Remove swatch safely'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pixels using this index will use the replacement. This can change their colors. Palette indices are remapped across frames; Undo restores the original.',
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
              ? 'Resolve each frame’s palette into RGBA pixels. Appearance is retained; native palette indices become colors. Undo restores indexed mode.'
              : 'Map pixels to each frame’s palette, reserving transparency. Colors and partial alpha may be approximated. This affects the whole document and can be undone. Keep an original copy.',
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

  @override
  Widget build(BuildContext context) {
    final colors = e.palette;
    final indexed = e.state['depth'] == 8;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 650),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Palette · ${indexed
                          ? 'Indexed'
                          : e.state['depth'] == 16
                          ? 'Grayscale'
                          : 'RGBA'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close palette',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      indexed
                          ? 'Choose an exact index, including duplicate-color swatches. Color edits affect this frame; reordering/removal remaps indices across the document.'
                          : 'Manage the document palette or convert to native indexed editing.',
                    ),
                    const SizedBox(height: 12),
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
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Color(colors[i]),
                                    border: Border.all(
                                      color: selected == i
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.grey,
                                      width: selected == i ? 4 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color:
                                          Color(colors[i]).computeLuminance() >
                                              .5
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hex,
                      enabled: !e.busy,
                      decoration: const InputDecoration(
                        labelText: 'Color · AARRGGBB',
                        helperText: 'AA is opacity: FF opaque, 00 transparent',
                      ),
                      autocorrect: false,
                    ),
                    TextField(
                      controller: name,
                      enabled: !e.busy,
                      decoration: const InputDecoration(
                        labelText: 'Swatch name (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilledButton(
                          onPressed: e.busy || colors.isEmpty
                              ? null
                              : () async {
                                  final c = _color();
                                  if (c != null) {
                                    await _edit('paletteEdit', {
                                      'index': selected,
                                      'color': c,
                                      'name': name.text,
                                    });
                                  }
                                },
                          child: const Text('Apply swatch'),
                        ),
                        OutlinedButton(
                          onPressed: e.busy
                              ? null
                              : () async {
                                  final c = _color();
                                  if (c != null) {
                                    await _edit('paletteAdd', {
                                      'color': c,
                                      'name': name.text,
                                    });
                                  }
                                },
                          child: const Text('Add swatch'),
                        ),
                        IconButton(
                          tooltip: 'Move swatch earlier',
                          onPressed: e.busy || selected == 0
                              ? null
                              : () async {
                                  final to = selected - 1;
                                  if (await _edit('paletteMove', {
                                    'index': selected,
                                    'to': to,
                                  })) {
                                    setState(() {
                                      selected = to;
                                      _load();
                                    });
                                  }
                                },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        IconButton(
                          tooltip: 'Move swatch later',
                          onPressed: e.busy || selected >= colors.length - 1
                              ? null
                              : () async {
                                  final to = selected + 1;
                                  if (await _edit('paletteMove', {
                                    'index': selected,
                                    'to': to,
                                  })) {
                                    setState(() {
                                      selected = to;
                                      _load();
                                    });
                                  }
                                },
                          icon: const Icon(Icons.arrow_forward),
                        ),
                        OutlinedButton(
                          onPressed: e.busy || colors.length < 2
                              ? null
                              : _remove,
                          child: const Text('Remove…'),
                        ),
                      ],
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const Divider(),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: e.busy ? null : _convert,
                          child: Text(
                            indexed
                                ? 'Convert to RGBA…'
                                : 'Convert to indexed…',
                          ),
                        ),
                        TextButton(
                          onPressed: !e.busy && e.canUndo
                              ? () => _history('undo')
                              : null,
                          child: const Text('Undo'),
                        ),
                        TextButton(
                          onPressed: !e.busy && e.canRedo
                              ? () => _history('redo')
                              : null,
                          child: const Text('Redo'),
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
    );
  }
}
