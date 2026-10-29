import 'dart:typed_data';
import 'document.dart';

int _integer(Map<String, dynamic> a, String key) {
  final value = a[key];
  require(value is int, 'Invalid region $key');
  return value as int;
}

(int, int, int, int) regionBounds(SpriteDocument d, Map<String, dynamic> a) {
  final x = _integer(a, 'x'), y = _integer(a, 'y');
  final w = _integer(a, 'width'), h = _integer(a, 'height');
  require(
    x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= d.width && y + h <= d.height,
    'Selection is outside the canvas',
  );
  return (x, y, w, h);
}

/// Detached native values: indexed colors (including duplicate entries) survive.
Map<String, dynamic> copyRegion(
  SpriteDocument d,
  int frame,
  int layer,
  Map<String, dynamic> a,
) {
  final (x, y, w, h) = regionBounds(d, a);
  require(d.layers[layer].visible, 'Show this layer before copying');
  require(
    w * h <= 1048576,
    'Selection clipboard is limited to 1,048,576 pixels',
  );
  final c = d.resolved(frame, layer);
  final empty = d.depth == 8 ? d.transparentIndex : 0;
  final data = ByteData(w * h * 4);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final sx = x + i, sy = y + j;
      final value =
          c != null &&
              sx >= c.x &&
              sy >= c.y &&
              sx < c.x + c.width &&
              sy < c.y + c.height
          ? c.pixels[(sy - c.y) * c.width + sx - c.x]
          : empty;
      data.setUint32((j * w + i) * 4, value, Endian.little);
    }
  }
  return {
    'width': w,
    'height': h,
    'depth': d.depth,
    'transparentIndex': d.transparentIndex,
    'palette': List<int>.of(d.frames[frame].palette),
    'pixels': data.buffer.asUint8List(),
  };
}

void editRegion(
  SpriteDocument d,
  int frame,
  int layer,
  Map<String, dynamic> a,
) {
  require(d.layers[layer].visible, 'Show this layer before editing');
  require(d.layers[layer].flags & 2 != 0, 'This layer is locked');
  require(
    d.layers[layer].flags & 8 == 0,
    'Convert this background layer to transparent before editing a region',
  );
  final (x, y, w, h) = regionBounds(d, a);
  final operation = a['operation'];
  require(
    const {'delete', 'move', 'paste'}.contains(operation),
    'Unknown region operation',
  );
  Map<String, dynamic>? copied;
  var tx = x, ty = y;
  if (operation == 'move') {
    tx += _integer(a, 'dx');
    ty += _integer(a, 'dy');
    regionBounds(d, {'x': tx, 'y': ty, 'width': w, 'height': h});
    copied = copyRegion(d, frame, layer, a);
  } else if (operation == 'paste') {
    require(a['clipboard'] is Map, 'Copy a region first');
    copied = Map<String, dynamic>.from(a['clipboard'] as Map);
    require(
      copied['depth'] == d.depth &&
          copied['width'] == w &&
          copied['height'] == h,
      'Incompatible selection clipboard',
    );
    if (d.depth == 8) {
      final palette = copied['palette'];
      require(
        copied['transparentIndex'] == d.transparentIndex &&
            palette is List &&
            palette.length == d.frames[frame].palette.length &&
            List.generate(
              palette.length,
              (i) =>
                  ((palette[i] as num).toInt() & 0xffffffff) ==
                  d.frames[frame].palette[i],
            ).every((same) => same),
        'Selection palette differs from this frame',
      );
    }
  }
  final pixels = copied?['pixels'];
  if (copied != null) {
    require(
      pixels is Uint8List && pixels.length == w * h * 4 && w * h <= 1048576,
      'Invalid clipboard pixels',
    );
  }
  final values = pixels is Uint8List ? ByteData.sublistView(pixels) : null;
  if (values != null && d.depth == 8) {
    for (var i = 0; i < w * h; i++) {
      require(
        values.getUint32(i * 4, Endian.little) < d.frames[frame].palette.length,
        'Invalid clipboard index',
      );
    }
  }
  final c = d.editable(frame, layer);
  final empty = d.depth == 8 ? d.transparentIndex : 0;
  if (operation != 'paste') {
    for (var j = y; j < y + h; j++) {
      for (var i = x; i < x + w; i++) {
        c.pixels[(j - c.y) * c.width + i - c.x] = empty;
      }
    }
  }
  if (values != null) {
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        c.pixels[(ty + j - c.y) * c.width + tx + i - c.x] = values.getUint32(
          (j * w + i) * 4,
          Endian.little,
        );
      }
    }
  }
}
