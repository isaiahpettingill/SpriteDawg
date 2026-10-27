import 'dart:convert';

import 'package:flutter/material.dart';

import 'color_picker.dart';

/// A staged palette edit, independent of both document and persistent library.
final class PresetDraft {
  PresetDraft({
    required this.name,
    required List<int> colors,
    required List<String> colorNames,
  }) : colors = List<int>.unmodifiable(colors),
       colorNames = List<String>.unmodifiable(colorNames);

  final String name;
  final List<int> colors;
  final List<String> colorNames;
}

Future<PresetDraft?> showPresetColorEditor(
  BuildContext context, {
  required String name,
  required List<int> colors,
  required List<String> colorNames,
}) => showDialog<PresetDraft>(
  context: context,
  builder: (_) => _PresetColorEditor(
    name: name,
    colors: List<int>.of(colors),
    colorNames: List<String>.of(colorNames),
  ),
);

class _DraftColor {
  _DraftColor(this.color, this.name);
  int color;
  String name;
}

class _PresetColorEditor extends StatefulWidget {
  const _PresetColorEditor({
    required this.name,
    required this.colors,
    required this.colorNames,
  });
  final String name;
  final List<int> colors;
  final List<String> colorNames;

  @override
  State<_PresetColorEditor> createState() => _PresetColorEditorState();
}

class _PresetColorEditorState extends State<_PresetColorEditor> {
  late String name = widget.name;
  late final List<_DraftColor> entries = [
    for (var i = 0; i < widget.colors.length; i++)
      _DraftColor(
        widget.colors[i],
        i < widget.colorNames.length ? widget.colorNames[i] : '',
      ),
  ];

  bool get valid =>
      name.trim().isNotEmpty &&
      name.trim().length <= 80 &&
      !name.contains(RegExp(r'[\x00-\x1f]')) &&
      entries.isNotEmpty &&
      entries.length <= 256 &&
      entries.every((e) => utf8.encode(e.name).length <= 65535);

  Future<void> change(_DraftColor entry) async {
    final color = await showSpriteColorPicker(
      context,
      initialColor: entry.color,
      title: 'Palette color',
    );
    if (!mounted || color == null || !entries.contains(entry)) return;
    setState(() => entry.color = color);
  }

  Future<void> add() async {
    if (entries.length >= 256) return;
    final color = await showSpriteColorPicker(
      context,
      initialColor: entries.isEmpty ? 0xffffffff : entries.last.color,
      title: 'Add palette color',
    );
    if (!mounted || color == null || entries.length >= 256) return;
    setState(() => entries.add(_DraftColor(color, '')));
  }

  void move(int from, int to) {
    setState(() {
      final entry = entries.removeAt(from);
      entries.insert(to, entry);
    });
  }

  void save() {
    if (!valid) return;
    Navigator.pop(
      context,
      PresetDraft(
        name: name.trim(),
        colors: entries.map((e) => e.color).toList(),
        colorNames: entries.map((e) => e.name).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
      child: CustomScrollView(
        shrinkWrap: true,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit palette',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('preset-edit-name'),
                    initialValue: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (value) => setState(() => name = value),
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: 'Add color',
                        child: TextButton.icon(
                          key: const Key('preset-edit-add'),
                          onPressed: entries.length < 256 ? add : null,
                          icon: const Icon(Icons.add),
                          label: Text('${entries.length}/256'),
                        ),
                      ),
                      TextButton(
                        key: const Key('preset-edit-cancel'),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const Key('preset-edit-save'),
                        onPressed: valid ? save : null,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final entry = entries[index];
              return Padding(
                key: ObjectKey(entry),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          key: Key('preset-edit-color-$index'),
                          tooltip: 'Edit color ${index + 1}',
                          onPressed: () => change(entry),
                          icon: BrushColorSwatch(color: entry.color),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ObjectKey(entry),
                            initialValue: entry.name,
                            decoration: InputDecoration(
                              labelText: 'Color ${index + 1}',
                              counterText: '',
                              helperText:
                                  '#${entry.color.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                            ),
                            onChanged: (value) =>
                                setState(() => entry.name = value),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Move color ${index + 1} up',
                          onPressed: index > 0
                              ? () => move(index, index - 1)
                              : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Move color ${index + 1} down',
                          onPressed: index + 1 < entries.length
                              ? () => move(index, index + 1)
                              : null,
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          key: Key('preset-edit-remove-$index'),
                          tooltip: 'Remove color ${index + 1}',
                          onPressed: entries.length > 1
                              ? () => setState(() => entries.remove(entry))
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }, childCount: entries.length),
          ),
        ],
      ),
    ),
  );
}
