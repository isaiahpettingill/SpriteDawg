import 'dart:convert';
import 'package:web/web.dart' as web;

Future<File> paletteLibraryFile() async =>
    File('spritedawg.palette-library.v1');

// A minimal storage adapter keeps validation/transaction semantics identical to
// native. localStorage.setItem either succeeds atomically or throws on quota.
class File {
  File(this.path);
  final String path;
  _Directory get parent => _Directory();
  Future<bool> exists() async => web.window.localStorage.getItem(path) != null;
  Future<int> length() async => utf8.encode(await readAsString()).length;
  Future<String> readAsString() async =>
      web.window.localStorage.getItem(path) ?? '';
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    web.window.localStorage.setItem(path, utf8.decode(bytes));
  }

  Future<void> rename(String destination) async {
    web.window.localStorage.setItem(destination, await readAsString());
    web.window.localStorage.removeItem(path);
  }

  Future<void> delete() async => web.window.localStorage.removeItem(path);
}

class _Directory {
  Future<void> create({bool recursive = false}) async {}
}
