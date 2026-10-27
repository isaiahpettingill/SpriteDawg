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

typedef EditorImageDecoder =
    Future<ui.Image> Function(
      Uint8List pixels, {
      required int width,
      required int height,
    });

class Editor extends ChangeNotifier {
  Editor({EditorTransport? transport, this.decodeImage = decodeStraightRgba})
    : transport =
          transport ??
          (defaultTargetPlatform == TargetPlatform.linux
              ? DesktopBackend().invoke
              : _native);
  final EditorTransport transport;
  final EditorImageDecoder decodeImage;
  static Future<Map<String, dynamic>?> _native(
    String method,
    Map<String, dynamic>? args,
  ) => channel.invokeMapMethod<String, dynamic>(method, args);
  static const channel = MethodChannel('pocketpixel/editor');
  Map<String, dynamic> state = {};
  ui.Image? image, previous, next;
  bool _slideViewEnabled = false, _slideLoading = false;
  int _slideEpoch = 0;
  (int, int)? _slideKey;
  final _viewChanges = _EditorSignal();
  Listenable get viewChanges => _viewChanges;
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
  String? imageOperation;
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
    return decodeImage(data, width: width, height: height);
  }

  /// View-only decoding is separate from stroke commits and never delays input.
  void setSlideViewEnabled(bool enabled) {
    if (_disposed || enabled == _slideViewEnabled) return;
    _slideViewEnabled = enabled;
    _slideEpoch++;
    if (!enabled) {
      next?.dispose();
      next = null;
      _slideKey = null;
      _viewChanges.emit();
    } else {
      _scheduleSlidePreview();
    }
  }

  void _scheduleSlidePreview() {
    if (_disposed || !_slideViewEnabled) return;
    final key = (documentRevision, frame);
    if (key != _slideKey) {
      _slideEpoch++;
      _slideKey = key;
      next?.dispose();
      next = null;
      _viewChanges.emit();
    }
    scheduleMicrotask(_loadSlidePreview);
  }

  Future<void> _loadSlidePreview() async {
    if (_disposed ||
        !_slideViewEnabled ||
        busy ||
        _slideLoading ||
        next != null) {
      return;
    }
    final count = (state['frames'] as List? ?? const []).length;
    if (frame + 1 >= count) return;
    final epoch = _slideEpoch;
    final index = frame + 1, w = width, h = height;
    _slideLoading = true;
    ui.Image? decoded;
    try {
      final result = await transport('frameImage', {'frame': index});
      if (_disposed || !_slideViewEnabled || epoch != _slideEpoch) return;
      final data = result?['pixels'];
      if (result?['frame'] != index ||
          result?['width'] != w ||
          result?['height'] != h ||
          data is! Uint8List ||
          data.length != w * h * 4) {
        return;
      }
      decoded = await decodeImage(data, width: w, height: h);
      if (_disposed || !_slideViewEnabled || epoch != _slideEpoch) return;
      next = decoded;
      decoded = null;
      _viewChanges.emit();
    } catch (_) {
      // A neighbor preview must never fail the edit or replace document state.
    } finally {
      decoded?.dispose();
      _slideLoading = false;
      if (!_disposed && _slideViewEnabled && epoch != _slideEpoch) {
        scheduleMicrotask(_loadSlidePreview);
      }
    }
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
        imageOperation = method;
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
      _scheduleSlidePreview();
    }
  }

  /// One immutable export transaction. No selected frame, dirty flag, history,
  /// project path or recovery copy is changed, including on cancellation.
  Future<bool> exportMedia(
    Map<String, dynamic> selection,
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>) encode,
  ) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final snapshot = await transport('exportSnapshot', selection);
      if (snapshot == null || _disposed) return false;
      final output = await encode(snapshot);
      if (output == null || _disposed) return false;
      final result = await transport('saveExport', output);
      return result?['saved'] == true;
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
      return false;
    } catch (e) {
      error = 'Export failed: $e';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
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
    _slideEpoch++;
    next?.dispose();
    next = null;
    _viewChanges.dispose();
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
