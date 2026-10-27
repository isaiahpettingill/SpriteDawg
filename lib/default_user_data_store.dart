import 'dart:convert';
import 'platform/default_user_data_io.dart'
    if (dart.library.js_interop) 'platform/default_user_data_web.dart';

/// Raw UTF-8 text, deliberately not parsed, trimmed or interpolated.
class DefaultUserDataStore {
  DefaultUserDataStore({required this.read, required this.write});
  static final shared = DefaultUserDataStore(
    read: readDefaultUserData,
    write: writeDefaultUserData,
  );
  factory DefaultUserDataStore.memory([String initial = '']) {
    var text = initial;
    return DefaultUserDataStore(
      read: () async => text,
      write: (value) async {
        text = value;
      },
    );
  }
  final Future<String> Function() read;
  final Future<void> Function(String) write;
  Future<void> _pending = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static void validate(String text) {
    if (utf8.encode(text).length > 65535) {
      throw const FormatException('User data exceeds 65,535 UTF-8 bytes.');
    }
  }

  Future<String> load() => _serial(() async {
    final text = await read();
    validate(text);
    return text;
  });
  Future<void> save(String text) => _serial(() async {
    validate(text);
    await write(text);
  });
}
