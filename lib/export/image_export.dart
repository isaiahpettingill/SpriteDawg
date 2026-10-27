import '../platform/run_background.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

import 'avif_native.dart' if (dart.library.js_interop) 'avif_web.dart';
import 'package:image/image.dart' as img;
import 'vendor/imcodec_qoi_encoder.dart' as qoi;

/// Encoding operates only on a detached snapshot; it never changes the document.
enum ImageExportFormat { gif, apng, webp, qoi, avif }

const maxExportRgbaBytes = 64 * 1024 * 1024;

class ImageExportPayload {
  const ImageExportPayload({
    required this.width,
    required this.height,
    required this.rgbaFrames,
    required this.durationMs,
    this.loopCount = 0,
  });

  final int width;
  final int height;

  /// Full-canvas, straight-alpha RGBA8 frames, in playback order.
  final List<Uint8List> rgbaFrames;
  final List<int> durationMs;

  /// Total plays, with zero meaning forever (normalized for GIF repeats).
  final int loopCount;

  void validate(ImageExportFormat format) {
    if (width < 1 ||
        height < 1 ||
        width > 16383 ||
        height > 16383 ||
        rgbaFrames.isEmpty ||
        rgbaFrames.length != durationMs.length ||
        width * height * 4 * rgbaFrames.length > maxExportRgbaBytes ||
        loopCount < 0 ||
        loopCount > 65535) {
      throw const FormatException(
        'Invalid export dimensions, frame count, or 64 MiB frame budget exceeded.',
      );
    }
    if ((format == ImageExportFormat.qoi || format == ImageExportFormat.avif) &&
        rgbaFrames.length != 1) {
      throw const FormatException('QOI and AVIF export a single frame only.');
    }
    if (format == ImageExportFormat.avif && (width < 16 || height < 16)) {
      throw const FormatException(
        'AVIF requires a canvas at least 16 × 16 pixels. Use PNG, WebP or QOI for smaller artwork.',
      );
    }
    for (var i = 0; i < rgbaFrames.length; i++) {
      if (rgbaFrames[i].length != width * height * 4 ||
          durationMs[i] < 1 ||
          durationMs[i] > 65535) {
        throw const FormatException(
          'Invalid RGBA byte length or frame duration.',
        );
      }
    }
  }
}

/// Call on the Flutter root isolate, where the AVIF plugin is registered.
/// The pure-Dart codecs run on a worker isolate. AVIF has its own native worker.
Future<Uint8List> encodeImageExport(
  ImageExportPayload payload,
  ImageExportFormat format,
) async {
  payload.validate(format);
  if (kIsWeb && format == ImageExportFormat.avif) {
    throw UnsupportedError('AVIF export is available in the installed app.');
  }
  if (format != ImageExportFormat.avif) {
    return runBackground(() => encodeImageExportSync(payload, format));
  }
  return encodeNativeAvif(payload);
}

/// Pure Dart entry point, suitable for isolates and deterministic codec tests.
Uint8List encodeImageExportSync(
  ImageExportPayload payload,
  ImageExportFormat format,
) {
  payload.validate(format);
  if (format == ImageExportFormat.avif) {
    throw ArgumentError('AVIF requires the asynchronous native encoder.');
  }
  if (format == ImageExportFormat.qoi) return _encodeQoi(payload);
  img.Image frame(int index) {
    final bytes = payload.rgbaFrames[index];
    return img.Image.fromBytes(
      width: payload.width,
      height: payload.height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
      frameDuration: payload.durationMs[index],
      frameType: img.FrameType.animation,
      loopCount: payload.loopCount,
    );
  }

  if (format == ImageExportFormat.gif) {
    final encoder = img.GifEncoder(
      repeat: payload.loopCount > 0 ? payload.loopCount - 1 : 0,
      dither: img.DitherKernel.none,
      dispose: 2,
    );
    for (var i = 0; i < payload.rgbaFrames.length; i++) {
      // GIF supports binary alpha and 10 ms timing, unlike APNG/WebP.
      final image = _gifPalette(frame(i));
      encoder.addFrame(
        image,
        duration: (payload.durationMs[i] / 10).round().clamp(1, 65535),
      );
    }
    final bytes = encoder.finish()!;
    if (payload.loopCount != 1) return bytes;
    // image 4.12.0 always emits the 19-byte NETSCAPE extension immediately
    // after its 13-byte header (with no global palette). Omitting it means
    // play once; an extension with repeat=0 would instead mean forever.
    if (bytes[13] != 0x21 ||
        bytes[14] != 0xff ||
        String.fromCharCodes(bytes.sublist(16, 27)) != 'NETSCAPE2.0') {
      throw StateError('Unexpected GIF application extension layout');
    }
    return (BytesBuilder(copy: false)
          ..add(bytes.sublist(0, 13))
          ..add(bytes.sublist(32)))
        .takeBytes();
  }
  final animation = frame(0);
  for (var i = 1; i < payload.rgbaFrames.length; i++) {
    animation.addFrame(frame(i));
  }
  return switch (format) {
    ImageExportFormat.apng => img.encodePng(animation),
    ImageExportFormat.webp => img.encodeWebP(
      animation,
      lossless: true,
      exact: true,
    ),
    _ => throw StateError('Unsupported image export format'),
  };
}

// image's RGB quantizers discard alpha. Reserve palette index zero explicitly
// so transparent pixels cannot become opaque during palette conversion.
img.Image _gifPalette(img.Image source) {
  final colors = <int, int>{};
  var transparent = false;
  for (final pixel in source) {
    if (pixel.a < 128) {
      transparent = true;
    } else if (colors.length <= 256) {
      final rgb =
          (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
      colors.putIfAbsent(rgb, () => colors.length);
    }
  }
  final offset = transparent ? 1 : 0;
  final limit = 256 - offset;
  final palette = img.PaletteUint8(256, 4);
  // Unused palette entries are opaque; only reserved index zero is clear.
  for (var i = offset; i < 256; i++) {
    palette.setRgba(i, 0, 0, 0, 255);
  }
  final img.OctreeQuantizer? quantizer;
  if (colors.length <= limit) {
    quantizer = null;
    for (final entry in colors.entries) {
      palette.setRgba(
        entry.value + offset,
        entry.key >> 16,
        (entry.key >> 8) & 255,
        entry.key & 255,
        255,
      );
    }
  } else {
    quantizer = img.OctreeQuantizer(source, numberOfColors: limit);
    for (var i = 0; i < quantizer.palette.numColors; i++) {
      palette.setRgba(
        i + offset,
        quantizer.palette.getRed(i),
        quantizer.palette.getGreen(i),
        quantizer.palette.getBlue(i),
        255,
      );
    }
  }
  final indexed = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 1,
    palette: palette,
    frameDuration: source.frameDuration,
  );
  for (final pixel in source) {
    final rgb =
        (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
    indexed.setPixelIndex(
      pixel.x,
      pixel.y,
      pixel.a < 128
          ? 0
          : (quantizer?.getColorIndex(pixel) ?? colors[rgb]!) + offset,
    );
  }
  return indexed;
}

Uint8List _encodeQoi(ImageExportPayload payload) => const qoi.QoiEncoder()
    .encode(payload.rgbaFrames.single, payload.width, payload.height);
