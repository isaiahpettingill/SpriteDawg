import '../engine/document.dart';

const exportPixelBudget = 8 * 1024 * 1024;

/// Detached straight-RGBA frames. Export never changes selection or document.
Map<String, dynamic> exportSnapshot(
  SpriteDocument document,
  int current,
  Map<String, dynamic> args,
) {
  final scope = args['scope'] as String? ?? 'current';
  var from = current, to = current, direction = 0, repeat = 0;
  if (scope == 'all') {
    from = 0;
    to = document.frames.length - 1;
  } else if (scope == 'tag') {
    final index = args['tag'] as int? ?? -1;
    require(
      index >= 0 && index < document.tags.length,
      'Select an existing tag',
    );
    final tag = document.tags[index];
    from = tag.from;
    to = tag.to;
    direction = tag.direction;
    repeat = tag.repeat;
  } else {
    require(scope == 'current', 'Invalid export selection');
  }
  require(
    from >= 0 && to >= from && to < document.frames.length,
    'Invalid export frame range',
  );
  final indices = [for (var i = from; i <= to; i++) i];
  if (args['animation'] == true) {
    if (direction == 1 || direction == 3) {
      final reversed = indices.reversed.toList();
      indices
        ..clear()
        ..addAll(reversed);
    }
    if ((direction == 2 || direction == 3) && indices.length > 2) {
      indices.addAll(indices.sublist(1, indices.length - 1).reversed.toList());
    }
  }
  require(
    document.width * document.height * indices.length <= exportPixelBudget,
    'Export is too large. Export fewer frames (32 MiB pixel limit).',
  );
  return {
    'width': document.width,
    'height': document.height,
    'frames': [for (final i in indices) rgbaBytes(document.composite(i))],
    'durations': [for (final i in indices) document.frames[i].duration],
    'indices': indices,
    'repeat': repeat,
    'tags': [
      for (final t in document.tags)
        if (t.from >= from && t.to <= to)
          {
            'name': t.name,
            'from': t.from - from,
            'to': t.to - from,
            'direction': t.direction,
            'repeat': t.repeat,
          },
    ],
  };
}
