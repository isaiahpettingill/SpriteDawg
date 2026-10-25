import 'platform/desktop_backend.dart';
import 'rgba_image.dart';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef EditorTransport =
    Future<Map<String, dynamic>?> Function(
      String method,
      Map<String, dynamic>? arguments,
    );

class Editor extends ChangeNotifier {
  Editor({EditorTransport? transport})
    : transport =
          transport ??
          (defaultTargetPlatform == TargetPlatform.linux
              ? DesktopBackend().invoke
              : _native);
  final EditorTransport transport;
  static Future<Map<String, dynamic>?> _native(
    String method,
    Map<String, dynamic>? args,
  ) => channel.invokeMapMethod<String, dynamic>(method, args);
  static const channel = MethodChannel('pocketpixel/editor');
  Map<String, dynamic> state = {};
  ui.Image? image, previous;
  bool busy = false;
  bool _disposed = false;
  String? error;
  int revision = 0;
  int get width => state['width'] as int? ?? 32;
  int get height => state['height'] as int? ?? 32;
  int get frame => state['frame'] as int? ?? 0;
  int get layer => state['layer'] as int? ?? 0;
  bool get dirty => state['dirty'] == true;
  bool get canUndo => state['canUndo'] == true;
  bool get canRedo => state['canRedo'] == true;
  List<Map<String, dynamic>> maps(String key) => (state[key] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  List<int> get palette =>
      (state['palette'] as List? ?? [0xff000000, 0xffffffff]).cast<int>();
  Future<ui.Image?> _decode(dynamic data) async {
    if (data is! Uint8List || data.length != width * height * 4) return null;
    return decodeStraightRgba(data, width: width, height: height);
  }

  Future<bool> call(String method, [Map<String, dynamic>? args]) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await transport(method, args);
      if (_disposed) return false;
      if (result != null) {
        state = Map<String, dynamic>.from(result);
        final next = await _decode(state['pixels']);
        final prev = await _decode(state['previousPixels']);
        if (_disposed) {
          next?.dispose();
          prev?.dispose();
          return false;
        }
        image?.dispose();
        previous?.dispose();
        image = next;
        previous = prev;
        revision++;
      }
      return true;
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
      return false;
    } catch (e) {
      error = 'Could not complete $method: $e';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> edit(String action, [Map<String, dynamic> args = const {}]) =>
      call('edit', {'action': action, ...args});
  @override
  void dispose() {
    _disposed = true;
    image?.dispose();
    previous?.dispose();
    super.dispose();
  }
}
