import 'platform/desktop_backend.dart';
import 'rgba_image.dart';
import 'frame_thumbnails.dart';

import 'dart:ui' as ui;
import 'dart:async';

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
  bool get busyDrawing => busy && _drawing;
  bool _drawing = false;
  Completer<void>? _operationDone;

  /// Pixel-only changes repaint the canvas without rebuilding editor controls.
  final _imageChanges = _EditorSignal();
  Listenable get imageChanges => _imageChanges;

  /// Thumbnails subscribe independently of the surrounding editor layout.
  final _documentChanges = _EditorSignal();
  Listenable get documentChanges => _documentChanges;
  bool _disposed = false;
  String? error;
  int revision = 0;
  int documentRevision = 0;
  late final FrameThumbnailCache _thumbnails = FrameThumbnailCache(transport);
  Future<ui.Image?> thumbnail(int frame) => _thumbnails.get(frame);
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
    // Rapid strokes are ordered, never silently dropped during image decoding.
    // A file/selection operation remains a hard boundary and rejects new input.
    while (method == 'stroke' && busyDrawing && !_disposed) {
      await _operationDone!.future;
    }
    if (busy || _disposed) return false;
    final oldState = state;
    final oldError = error;
    final drawing = method == 'stroke';
    var pixelsChanged = false, documentChanged = false;
    _operationDone = Completer<void>();
    busy = true;
    _drawing = drawing;
    error = null;
    if (!drawing) notifyListeners();
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
        pixelsChanged = true;
        if (!const {
          'select',
          'state',
          'save',
          'saveAs',
          'exportPng',
          'discardRecovery',
          'copyTag',
          'clearTagClipboard',
        }.contains(method)) {
          documentRevision++;
          _thumbnails.invalidate();
          documentChanged = true;
        }
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
      _drawing = false;
      final finished = _operationDone;
      _operationDone = null;
      if (!_disposed) {
        if (pixelsChanged) _imageChanges.emit();
        if (documentChanged) _documentChanges.emit();
        if (!drawing || oldError != error || !_sameControls(oldState, state)) {
          notifyListeners();
        }
      }
      finished?.complete();
    }
  }

  static bool _sameControls(Map<String, dynamic> a, Map<String, dynamic> b) {
    const pixels = {'pixels', 'previousPixels'};
    final aKeys = a.keys.where((key) => !pixels.contains(key)).toSet();
    final bKeys = b.keys.where((key) => !pixels.contains(key)).toSet();
    return setEquals(aKeys, bKeys) &&
        aKeys.every((key) => _sameValue(a[key], b[key]));
  }

  static bool _sameValue(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameValue(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _sameValue(a[key], b[key]),
          );
    }
    return a == b;
  }

  Future<bool> edit(String action, [Map<String, dynamic> args = const {}]) =>
      call('edit', {'action': action, ...args});
  @override
  void dispose() {
    _disposed = true;
    _thumbnails.dispose();
    _imageChanges.dispose();
    _documentChanges.dispose();
    image?.dispose();
    previous?.dispose();
    super.dispose();
  }
}

class _EditorSignal extends ChangeNotifier {
  void emit() => notifyListeners();
}
