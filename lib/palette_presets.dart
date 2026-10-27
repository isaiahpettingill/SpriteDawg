import 'package:flutter/material.dart';

import 'engine/palette_presets.dart';
import 'color_picker.dart';
import 'user_palette_store.dart';
import 'preset_color_editor.dart';

Future<PalettePreset?> showPalettePresets(
  BuildContext context, {
  UserPaletteStore? store,
}) => showDialog<PalettePreset>(
  context: context,
  builder: (_) => PalettePresetPicker(store: store),
);

/// Offline palette library. Browsing and dismissing never edits the document.
class PalettePresetPicker extends StatefulWidget {
  const PalettePresetPicker({super.key, this.store});
  final UserPaletteStore? store;

  @override
  State<PalettePresetPicker> createState() => _PalettePresetPickerState();
}

class _PalettePresetPickerState extends State<PalettePresetPicker> {
  String query = '';
  List<PalettePreset> personal = const [];
  String? libraryError;
  bool managing = false;
  UserPaletteStore get store => widget.store ?? UserPaletteStore.shared;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final loaded = await store.load();
      if (mounted) {
        setState(() {
          personal = loaded;
          libraryError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => libraryError =
              'Could not read My palettes. Your saved file has not been changed.',
        );
      }
    }
  }

  Future<void> _manage(String action, PalettePreset palette) async {
    if (managing) return;
    setState(() => managing = true);
    try {
      if (action == 'details') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(palette.name),
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(palette.description),
                const SizedBox(height: 12),
                Text(palette.credit),
                Text(palette.license),
                if (palette.source.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(palette.source),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      if (action == 'delete') {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${palette.name}?'),
            content: const Text(
              'Remove this personal preset. Open documents are unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (accepted != true) return;
        await store.delete(palette.id);
      } else {
        final draft = await showPresetColorEditor(
          context,
          name: action == 'copy'
              ? '${palette.name.substring(0, palette.name.length > 75 ? 75 : palette.name.length)} copy'
              : palette.name,
          colors: palette.colors,
          colorNames: palette.colorNames,
        );
        if (draft == null) return;
        await store.save(
          name: draft.name,
          colors: draft.colors,
          colorNames: draft.colorNames,
          replaceId: action == 'edit' ? palette.id : null,
        );
      }
      await _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => libraryError =
              'Could not save My palettes. Your previous presets are unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => managing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = [...personal, ...palettePresets]
        .where(
          (p) =>
              '${p.name} ${p.description} ${p.credit} ${p.colorNames.join(' ')}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
        )
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        // The keyboard can leave less room than the header and search field
        // need in landscape. Let every part scroll, not only the results.
        child: CustomScrollView(
          shrinkWrap: true,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Preset palettes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Palette licenses',
                      onPressed: () => showLicensePage(context: context),
                      icon: const Icon(Icons.info_outline),
                    ),
                    IconButton(
                      tooltip: 'Close presets',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              // Keep the field in the same sliver across query changes so its
              // editable state and keyboard focus survive result-list rebuilds.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  key: const Key('palette-preset-search'),
                  decoration: const InputDecoration(
                    labelText: 'Search palettes',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
            ),
            if (libraryError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(libraryError!)),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (matches.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching palettes'),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index.isOdd) return const Divider(height: 1);
                  final paletteIndex = index ~/ 2;
                  final p = matches[paletteIndex];
                  final isPersonal = personal.any((saved) => saved.id == p.id);
                  final beginsSection =
                      paletteIndex == 0 ||
                      personal.any(
                            (saved) => saved.id == matches[paletteIndex - 1].id,
                          ) !=
                          isPersonal;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (beginsSection)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            isPersonal ? 'My palettes' : 'Built-in palettes',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ListTile(
                        key: Key('palette-preset-${p.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text('${p.name} · ${p.colors.length}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: '${p.name} options',
                          enabled: !managing,
                          onSelected: (action) => _manage(action, p),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'details',
                              child: Text('Details'),
                            ),
                            if (isPersonal)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit preset…'),
                              ),
                            const PopupMenuItem(
                              value: 'copy',
                              child: Text('Save a copy…'),
                            ),
                            if (isPersonal)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete preset…'),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              children: [
                                for (var i = 0; i < p.colors.length; i++)
                                  Tooltip(
                                    excludeFromSemantics: true,
                                    message: paletteSwatchLabel(
                                      p.colors[i],
                                      i < p.colorNames.length
                                          ? p.colorNames[i]
                                          : 'Swatch ${i + 1}',
                                    ),
                                    child: Semantics(
                                      label: paletteSwatchLabel(
                                        p.colors[i],
                                        i < p.colorNames.length
                                            ? p.colorNames[i]
                                            : 'Swatch ${i + 1}',
                                      ),
                                      child: BrushColorSwatch(
                                        key: Key('preset-${p.id}-swatch-$i'),
                                        color: p.colors[i],
                                        size: 18,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        onTap: managing
                            ? null
                            : () => Navigator.pop(context, p),
                      ),
                    ],
                  );
                }, childCount: matches.length * 2 - 1),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keep hexadecimal alpha and human-readable opacity together; percentages alone
/// cannot distinguish every 8-bit alpha value.
String paletteSwatchLabel(int color, String name) {
  final hex = color.toRadixString(16).padLeft(8, '0').toUpperCase();
  final opacity = ((color >> 24 & 255) * 100 / 255).round();
  return '$name · ARGB #$hex · $opacity% opacity';
}
