import 'dart:io';
import 'package:path_provider/path_provider.dart';
export 'dart:io' show File;

Future<File> paletteLibraryFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/palette-library.json');
}
