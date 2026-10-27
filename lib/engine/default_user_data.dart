import 'dart:convert';
import 'document.dart';

String defaultUserData(Map<String, dynamic> args) {
  final value = args['defaultUserData'] ?? '';
  require(value is String, 'Default user data must be text');
  final text = value as String;
  require(
    utf8.encode(text).length <= 65535,
    'User data exceeds 65,535 UTF-8 bytes',
  );
  return text;
}

SpriteDocument newSprite(int width, int height, String text) {
  defaultUserData({'defaultUserData': text});
  final document = SpriteDocument.create(width, height);
  if (text.isNotEmpty) document.data = UserData(text: text);
  return document;
}
