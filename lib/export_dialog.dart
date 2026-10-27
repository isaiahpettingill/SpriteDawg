import 'platform/run_background.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'editor.dart';
import 'engine/png.dart';
import 'export/image_export.dart';
import 'export/spritesheet.dart';

Future<void> showExportDialog(BuildContext context, Editor editor) async {
  final options = await showDialog<_ExportOptions>(
    context: context,
    builder: (_) => _ExportDialog(
      tags: editor.maps('tags'),
      avifAvailable: !kIsWeb && editor.width >= 16 && editor.height >= 16,
    ),
  );
  if (options == null || !context.mounted) return;
  final saved = await editor.exportMedia(
    {'scope': options.scope, 'tag': options.tag, 'animation': options.animated},
    (snapshot) async {
      final frames = (snapshot['frames'] as List).cast<Uint8List>();
      final gifColorLoss =
          options.format == 'gif' &&
          await runBackground(() => _gifLosesColors(frames));
      final gifTimingLoss =
          options.format == 'gif' &&
          (snapshot['durations'] as List).cast<int>().any(
            (duration) => duration % 10 != 0,
          );
      if (gifColorLoss || gifTimingLoss) {
        if (!context.mounted) return null;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export with GIF limits?'),
            content: Text(
              [
                if (gifColorLoss)
                  'Colors will be reduced to 256 per frame, with on/off transparency.',
                if (gifTimingLoss) 'Frame timing will be rounded to 10 ms.',
              ].join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Export GIF'),
              ),
            ],
          ),
        );
        if (proceed != true) return null;
      }
      Map<String, Uint8List> files;
      if (options.format == 'sheet') {
        files = await runBackground(
          () => encodeSpritesheet(
            snapshot,
            name: options.name,
            columns: options.columns,
            padding: options.padding,
          ),
        );
      } else if (options.format == 'png') {
        final bytes = await runBackground(
          () => encodeRgbaPng(
            frames.single,
            width: snapshot['width'] as int,
            height: snapshot['height'] as int,
          ),
        );
        files = {'${options.name}.png': bytes};
      } else {
        final format = ImageExportFormat.values.byName(options.format);
        final bytes = await encodeImageExport(
          ImageExportPayload(
            width: snapshot['width'] as int,
            height: snapshot['height'] as int,
            rgbaFrames: frames,
            durationMs: (snapshot['durations'] as List).cast<int>(),
            loopCount: options.loops,
          ),
          format,
        );
        files = {'${options.name}.${options.format}': bytes};
      }
      return {'name': options.name, 'files': files};
    },
  );
  if (!context.mounted) return;
  if (saved || editor.error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? (options.format == 'sheet'
                    ? (kIsWeb
                          ? 'Spritesheet and JSON download started (ZIP)'
                          : 'Spritesheet and JSON exported to a new folder')
                    : 'Exported')
              : editor.error!,
        ),
      ),
    );
  }
}

bool _gifLosesColors(List<Uint8List> frames) {
  for (final bytes in frames) {
    final colors = <int>{};
    for (var i = 0; i < bytes.length; i += 4) {
      final alpha = bytes[i + 3];
      if (alpha != 0 && alpha != 255) return true;
      colors.add(
        alpha == 0
            ? 0
            : (bytes[i] << 24) |
                  (bytes[i + 1] << 16) |
                  (bytes[i + 2] << 8) |
                  alpha,
      );
      if (colors.length > 256) return true;
    }
  }
  return false;
}

class _ExportOptions {
  const _ExportOptions({
    required this.name,
    required this.format,
    required this.scope,
    required this.tag,
    required this.columns,
    required this.padding,
    required this.loops,
  });
  final String name, format, scope;
  final int tag, columns, padding, loops;
  bool get animated => const ['gif', 'apng', 'webp'].contains(format);
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.tags, required this.avifAvailable});
  final bool avifAvailable;
  final List<Map<String, dynamic>> tags;
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(text: 'sprite');
  final columns = TextEditingController(text: '8');
  final padding = TextEditingController(text: '0');
  final loops = TextEditingController(text: '0');
  String format = 'png', scope = 'current';
  int tag = 0;
  bool get animated => const ['gif', 'apng', 'webp'].contains(format);
  bool get multiple => animated || format == 'sheet';
  @override
  void dispose() {
    name.dispose();
    columns.dispose();
    padding.dispose();
    loops.dispose();
    super.dispose();
  }

  String? number(String? value, int min, int max) {
    final n = int.tryParse(value ?? '');
    return n == null || n < min || n > max ? '$min–$max' : null;
  }

  void submit() {
    if (!(form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _ExportOptions(
        name: name.text.trim(),
        format: format,
        scope: multiple ? scope : 'current',
        tag: tag,
        columns: int.tryParse(columns.text) ?? 8,
        padding: int.tryParse(padding.text) ?? 0,
        loops: int.tryParse(loops.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Export')),
        IconButton(
          tooltip: 'Export help',
          icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Export formats'),
              content: const SingleChildScrollView(
                child: Text(
                  'PNG, QOI and AVIF export the current frame. GIF, APNG and WebP can animate frames or a tag.\n\nGIF has a 256-color limit, binary transparency and 10 ms timing. APNG and lossless WebP preserve full alpha. AVIF is lossy, including small transparency changes, and requires at least 16×16 pixels.\n\nSpritesheets use untrimmed PNG cells and Aseprite-style JSON. A new folder (ZIP download in the browser) keeps the pair together. Tag direction is applied to animations and recorded in sheet metadata. Loop count 0 means forever.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    scrollable: true,
    content: SizedBox(
      width: 380,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: format,
              decoration: const InputDecoration(labelText: 'Format'),
              items: [
                const DropdownMenuItem(value: 'png', child: Text('PNG')),
                const DropdownMenuItem(value: 'gif', child: Text('GIF')),
                const DropdownMenuItem(value: 'apng', child: Text('APNG')),
                const DropdownMenuItem(value: 'webp', child: Text('WebP')),
                const DropdownMenuItem(value: 'qoi', child: Text('QOI')),
                DropdownMenuItem(
                  value: 'avif',
                  enabled: widget.avifAvailable,
                  child: Text(
                    kIsWeb
                        ? 'AVIF (installed app)'
                        : widget.avifAvailable
                        ? 'AVIF (lossy)'
                        : 'AVIF (16×16 min)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const DropdownMenuItem(
                  value: 'sheet',
                  child: Text(
                    'Spritesheet + JSON',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                format = v!;
                if (!multiple) scope = 'current';
              }),
            ),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              maxLength: 64,
              validator: (v) =>
                  v == null ||
                      !RegExp(
                        r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$',
                      ).hasMatch(v.trim()) ||
                      v.trim().endsWith('.')
                  ? 'Use letters, numbers, spaces, - or _'
                  : null,
              onFieldSubmitted: (_) => submit(),
            ),
            if (multiple)
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('scope-$format'),
                initialValue: scope,
                decoration: const InputDecoration(labelText: 'Frames'),
                items: [
                  const DropdownMenuItem(
                    value: 'current',
                    child: Text(
                      'Current frame',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All frames'),
                  ),
                  if (widget.tags.isNotEmpty)
                    const DropdownMenuItem(value: 'tag', child: Text('Tag')),
                ],
                onChanged: (v) => setState(() {
                  scope = v!;
                  if (scope == 'tag') {
                    loops.text = '${widget.tags[tag]['repeat'] ?? 0}';
                  }
                }),
              ),
            if (multiple && scope == 'tag')
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: tag,
                decoration: const InputDecoration(labelText: 'Tag'),
                items: [
                  for (var i = 0; i < widget.tags.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        widget.tags[i]['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  tag = v!;
                  loops.text = '${widget.tags[tag]['repeat'] ?? 0}';
                }),
              ),
            if (format == 'sheet')
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: columns,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Columns'),
                      validator: (v) => number(v, 1, 64),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: padding,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Padding'),
                      validator: (v) => number(v, 0, 32),
                    ),
                  ),
                ],
              ),
            if (animated)
              TextFormField(
                controller: loops,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Loops (0 = forever)',
                ),
                validator: (v) => number(v, 0, 65535),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Export')),
    ],
  );
}
