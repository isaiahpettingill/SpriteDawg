import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart'
    as avif;
import 'image_export.dart' show ImageExportPayload;

bool _avifInFlight = false;
Future<Uint8List> encodeNativeAvif(ImageExportPayload payload) async {
  if (_avifInFlight) {
    throw StateError(
      'An AVIF export is still running. Use another format or restart the app if the previous export timed out.',
    );
  }
  _avifInFlight = true;
  // Bypass the convenience PNG decoder: it uses premultiplied rawRgba.
  // The native encoder takes straight RGBA. Zero quantizers select its highest
  // quality, but rav1e can still alter RGB AND alpha (including transparent
  // pixels). AVIF must not be advertised as lossless.
  final pending = Future<Uint8List>.sync(
    () => avif.FlutterAvifPlatform.api.encodeAvif(
      width: payload.width,
      height: payload.height,
      speed: 6,
      maxThreads: 2,
      timescale: 1,
      minQuantizer: 0,
      maxQuantizer: 0,
      minQuantizerAlpha: 0,
      maxQuantizerAlpha: 0,
      imageSequence: [
        avif.EncodeFrame(
          data: payload.rgbaFrames.single,
          durationInTimescale: 1,
        ),
      ],
      exifData: Uint8List(0),
    ),
  );
  // Release only when the underlying native work actually finishes, NOT when
  // timeout stops awaiting it. A stuck Android worker cannot be piled up.
  unawaited(
    pending.then<void>(
      (_) {
        _avifInFlight = false;
      },
      onError: (Object error, StackTrace stack) {
        _avifInFlight = false;
      },
    ),
  );
  final output = await pending.timeout(const Duration(seconds: 60));
  if (output.isEmpty) {
    throw const FormatException('AVIF encoder returned no image.');
  }
  return output;
}
