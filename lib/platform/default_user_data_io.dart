import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file() async => File(
  '${(await getApplicationSupportDirectory()).path}/default-user-data.txt',
);
Future<String> readDefaultUserData() async {
  final file = await _file();
  if (!await file.exists()) return '';
  if (await file.length() > 65535) {
    throw const FormatException('Saved user data is too large.');
  }
  return file.readAsString();
}

Future<void> writeDefaultUserData(String text) async {
  final file = await _file();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  try {
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
