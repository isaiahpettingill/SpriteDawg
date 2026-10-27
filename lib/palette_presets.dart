import 'package:flutter/material.dart';

import 'engine/palette_presets.dart';

Future<PalettePreset?> showPalettePresets(BuildContext context) =>
    showDialog<PalettePreset>(
      context: context,
      builder: (_) => const PalettePresetPicker(),
    );

/// Offline palette library. Browsing and dismissing never edits the document.
class PalettePresetPicker extends StatefulWidget {
  const PalettePresetPicker({super.key});

  @override
  State<PalettePresetPicker> createState() => _PalettePresetPickerState();
}

class _PalettePresetPickerState extends State<PalettePresetPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final matches = palettePresets
        .where(
          (p) => '${p.name} ${p.description} ${p.credit}'
              .toLowerCase()
              .contains(query.trim().toLowerCase()),
        )
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
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
            Padding(
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
            Flexible(
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching palettes'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = matches[index];
                        return ListTile(
                          key: Key('palette-preset-${p.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          title: Text('${p.name} · ${p.colors.length}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              ExcludeSemantics(
                                child: Wrap(
                                  spacing: 1,
                                  runSpacing: 1,
                                  children: [
                                    for (final color in p.colors)
                                      Container(
                                        width: 16,
                                        height: 16,
                                        color: Color(color),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(p.description),
                              Text(
                                p.credit,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
