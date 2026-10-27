import 'dart:js_interop';

@JS('globalThis.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}
const _key = 'spritedawg.default-user-data.v1';
Future<String> readDefaultUserData({String key = _key}) async =>
    _storage.getItem(key.toJS)?.toDart ?? '';
Future<void> writeDefaultUserData(String text, {String key = _key}) async =>
    _storage.setItem(key.toJS, text.toJS);
