import 'dart:typed_data';
import 'dart:ui' as ui;

import 'engine/document.dart' show maxPixels;

/// Converts the engines' straight-alpha RGBA bytes to a Flutter image.
///
/// Flutter's rgba8888 input expects *premultiplied* channels. Feeding straight
/// bytes to it brightens translucent artwork, while premultiplying in eight
/// bits loses low-alpha colors. Float RGBA explicitly uses straight alpha.
/// Opaque pixels and zero-RGB transparent pixels retain the exact eight-bit
/// fast path, so ordinary binary-transparency pixel art needs no float buffer.
/// The caller owns the returned image and must dispose it.
Future<ui.Image> decodeStraightRgba(
  Uint8List pixels, {
  required int width,
  required int height,
}) async {
  if (width < 1 ||
      height < 1 ||
      width > 65535 ||
      height > 65535 ||
      width * height > maxPixels ||
      pixels.length != width * height * 4) {
    throw const FormatException('Invalid RGBA image dimensions or byte length');
  }
  var premultipliedCompatible = true;
  for (var i = 3; i < pixels.length; i += 4) {
    if (pixels[i] != 255 &&
        (pixels[i - 3] != 0 || pixels[i - 2] != 0 || pixels[i - 1] != 0)) {
      premultipliedCompatible = false;
      break;
    }
  }
  Uint8List input = pixels;
  if (!premultipliedCompatible) {
    // At the document's four-megapixel limit this temporary is at most 64 MiB.
    final floats = Float32List(pixels.length);
    for (var i = 0; i < pixels.length; i++) {
      floats[i] = pixels[i] / 255.0;
    }
    input = floats.buffer.asUint8List();
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(input);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: premultipliedCompatible
          ? ui.PixelFormat.rgba8888
          : ui.PixelFormat.rgbaFloat32,
    );
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
