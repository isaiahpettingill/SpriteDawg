import 'dart:typed_data';
import 'image_export.dart' show ImageExportPayload;

Future<Uint8List> encodeNativeAvif(ImageExportPayload payload) async =>
    throw UnsupportedError('AVIF export is available in the installed app.');
