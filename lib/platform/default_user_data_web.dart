import 'dart:js_interop';

@JS('globalThis.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}
const _key = 'spritedawg.default-user-data.v1';
Future<String> readDefaultUserData() async =>
    _storage.getItem(_key.toJS)?.toDart ?? '';
Future<void> writeDefaultUserData(String text) async =>
    _storage.setItem(_key.toJS, text.toJS);
