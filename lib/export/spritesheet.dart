import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'export_snapshot.dart';

/// Aseprite JSON-array layout, untrimmed and unrotated, with original durations.
Map<String, Uint8List> encodeSpritesheet(
  Map<String, dynamic> snapshot, {
  required String name,
  int columns = 8,
  int padding = 0,
}) {
  final width = snapshot['width'] as int;
  final height = snapshot['height'] as int;
  final frames = (snapshot['frames'] as List).cast<Uint8List>();
  final durations = (snapshot['durations'] as List).cast<int>();
  final indices = (snapshot['indices'] as List).cast<int>();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$').hasMatch(name) ||
      name.endsWith('.') ||
      columns < 1 ||
      columns > 64 ||
      padding < 0 ||
      padding > 32 ||
      width < 1 ||
      height < 1 ||
      frames.isEmpty ||
      durations.length != frames.length ||
      indices.length != frames.length) {
    throw const FormatException('Invalid spritesheet options');
  }
  columns = columns.clamp(1, frames.length);
  final rows = (frames.length + columns - 1) ~/ columns;
  final sheetWidth = columns * width + (columns + 1) * padding;
  final sheetHeight = rows * height + (rows + 1) * padding;
  if (sheetWidth > 32767 ||
      sheetHeight > 32767 ||
      sheetWidth * sheetHeight > exportPixelBudget) {
    throw const FormatException(
      'Spritesheet is too large. Use fewer frames or less padding.',
    );
  }
  final pixels = Uint8List(sheetWidth * sheetHeight * 4);
  final entries = <Map<String, dynamic>>[];
  for (var i = 0; i < frames.length; i++) {
    final frame = frames[i];
    if (frame.length != width * height * 4) {
      throw const FormatException('Invalid export frame');
    }
    final x = padding + i % columns * (width + padding);
    final y = padding + i ~/ columns * (height + padding);
    for (var row = 0; row < height; row++) {
      final start = ((y + row) * sheetWidth + x) * 4;
      pixels.setRange(start, start + width * 4, frame, row * width * 4);
    }
    entries.add({
      'filename': '$name-${indices[i]}.aseprite',
      'frame': {'x': x, 'y': y, 'w': width, 'h': height},
      'rotated': false,
      'trimmed': false,
      'spriteSourceSize': {'x': 0, 'y': 0, 'w': width, 'h': height},
      'sourceSize': {'w': width, 'h': height},
      'duration': durations[i],
    });
  }
  const directions = ['forward', 'reverse', 'pingpong', 'pingpong_reverse'];
  final tags = (snapshot['tags'] as List).cast<Map>();
  final metadata = {
    'frames': entries,
    'meta': {
      'app': 'SpriteDawg',
      'version': '1',
      'image': '$name.png',
      'format': 'RGBA8888',
      'size': {'w': sheetWidth, 'h': sheetHeight},
      'scale': '1',
      'frameTags': [
        for (final tag in tags)
          {
            'name': tag['name'],
            'from': tag['from'],
            'to': tag['to'],
            'direction': directions[(tag['direction'] as int).clamp(0, 3)],
            'repeat': tag['repeat'],
          },
      ],
    },
  };
  final image = img.Image.fromBytes(
    width: sheetWidth,
    height: sheetHeight,
    bytes: pixels.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return {
    '$name.png': img.encodePng(image),
    '$name.json': Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(metadata)),
    ),
  };
}
