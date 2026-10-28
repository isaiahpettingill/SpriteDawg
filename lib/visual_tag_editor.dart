import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import 'editor.dart';

/// Tags remain ordinary Aseprite ranges, useful for tiles and animations alike.
/// The shell keeps this widget mounted when its panel is hidden, so a name draft
/// is not silently discarded or committed by changing workspaces.
class VisualTagEditor extends StatefulWidget {
  const VisualTagEditor({
    super.key,
    required this.editor,
    required this.selectedTag,
    required this.onSelected,
    required this.onEdit,
    required this.onStop,
    required this.onData,
    required this.onEditingChanged,
    this.active = true,
  });
  final Editor editor;
  final int selectedTag;
  final bool active;
  final ValueChanged<int> onSelected;
  final Future<bool> Function(String, Map<String, dynamic>) onEdit;
  final VoidCallback onStop;
  final Future<void> Function(int) onData;
  final ValueChanged<bool> onEditingChanged;
  @override
  State<VisualTagEditor> createState() => VisualTagEditorState();
}

class VisualTagEditorState extends State<VisualTagEditor> {
  static const _frameWidth = 76.0, _gutter = 22.0;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _frames = ScrollController(), _chips = ScrollController();
  final _startFocus = FocusNode(), _endFocus = FocusNode();
  final _stripKey = GlobalKey();
  bool _creating = false, _naming = false, _working = false;
  int _from = 0, _to = 0, _lastFrame = -1;
  String _signature = '';
  Object? _document;
  _RangeDrag? _drag;
  Timer? _edgeScroll;

  Object? _tagSource;
  List<Map<String, dynamic>> _cachedTags = [];
  List<Map<String, dynamic>> get tags {
    final source = widget.editor.state['tags'];
    if (!identical(source, _tagSource)) {
      _tagSource = source;
      _cachedTags = widget.editor.maps('tags');
    }
    return _cachedTags;
  }

  int get count => (widget.editor.state['frames'] as List? ?? const []).length;
  int get selected =>
      widget.selectedTag >= 0 && widget.selectedTag < tags.length
      ? widget.selectedTag
      : -1;
  bool get hasRange => _creating || selected >= 0;
  bool get blocked => widget.editor.busy || _working;
  String get signature => selected < 0
      ? ''
      : '${tags[selected]['name']}\u0000${tags[selected]['from']}:${tags[selected]['to']}';

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_focusChanged);
    _load();
    _lastFrame = widget.editor.frame;
    _scheduleReveal();
  }

  void _focusChanged() => widget.onEditingChanged(_nameFocus.hasFocus);

  void _load() {
    _creating = false;
    _naming = false;
    _name.text = selected >= 0 ? tags[selected]['name'] as String : '';
    _from = selected >= 0 ? tags[selected]['from'] as int : 0;
    _to = selected >= 0
        ? tags[selected]['to'] as int
        : (count - 1).clamp(0, 4095);
    _signature = signature;
    _document = widget.editor.state['documentId'];
  }

  @override
  void didUpdateWidget(VisualTagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedDocument = _document != widget.editor.state['documentId'];
    final changedSelection = oldWidget.selectedTag != widget.selectedTag;
    if (_drag != null &&
        (!widget.active ||
            changedDocument ||
            changedSelection ||
            _drag!.revision != widget.editor.documentRevision)) {
      _endDragTimer();
      _drag = null;
      if (!_creating) {
        _from = selected >= 0 ? tags[selected]['from'] as int : 0;
        _to = selected >= 0 ? tags[selected]['to'] as int : 0;
      }
    }
    if (changedDocument ||
        changedSelection ||
        (_naming && !_creating && selected < 0) ||
        (!_working && !_creating && !_naming && _signature != signature)) {
      _load();
    } else if (!_working && !_creating && selected >= 0 && _drag == null) {
      // Undo or another edit may change a range while its name is being typed.
      // Keep the draft name, but never write stale endpoints back over that edit.
      _from = tags[selected]['from'] as int;
      _to = tags[selected]['to'] as int;
    }
    if (_from >= count || _to >= count) {
      if (_creating && count > 0) {
        _from = _from.clamp(0, count - 1);
        _to = _to.clamp(_from, count - 1);
      } else {
        _load();
      }
    }
    if (_lastFrame != widget.editor.frame ||
        (!oldWidget.active && widget.active) ||
        changedSelection) {
      _lastFrame = widget.editor.frame;
      _scheduleReveal(chips: changedSelection || !oldWidget.active);
    }
  }

  void _scheduleReveal({bool chips = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      _reveal(widget.editor.frame);
      if (chips) _revealTag();
    });
  }

  @override
  void dispose() {
    _endDragTimer();
    _nameFocus.removeListener(_focusChanged);
    _name.dispose();
    _nameFocus.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    _frames.dispose();
    _chips.dispose();
    super.dispose();
  }

  /// Panel navigation preserves the name draft but cancels an unfinished drag.
  void pauseEditing() {
    _cancelDrag();
    _nameFocus.unfocus();
  }

  void _reveal(int frame) {
    if (!mounted || !_frames.hasClients || _drag != null) return;
    final left = frame * _frameWidth + _gutter;
    final viewport = _frames.position.viewportDimension;
    if (left < _frames.offset ||
        left + _frameWidth > _frames.offset + viewport) {
      _frames.jumpTo(
        (left - viewport / 2 + _frameWidth / 2).clamp(
          0.0,
          _frames.position.maxScrollExtent,
        ),
      );
    }
  }

  double _chipWidth(int index) => index < 0
      ? 106
      : ((tags[index]['name'] as String).length * 7.0 + 24).clamp(100.0, 184.0);

  void _revealTag() {
    if (!_chips.hasClients || _creating) return;
    var left = 0.0;
    for (var i = -1; i < selected; i++) {
      left += _chipWidth(i);
    }
    final right = left + _chipWidth(selected);
    if (left < _chips.offset ||
        right > _chips.offset + _chips.position.viewportDimension) {
      _chips.jumpTo(left.clamp(0.0, _chips.position.maxScrollExtent));
    }
  }

  void _notice(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  Future<bool> savePending() async {
    if (_drag != null || blocked) return false;
    if (!_naming) return true;
    if (_name.text.trim().isEmpty) {
      _notice(
        widget.active
            ? 'Give this tag a name, or cancel.'
            : 'Open Tags to finish naming this tag, or cancel it.',
      );
      if (widget.active) _nameFocus.requestFocus();
      return false;
    }
    if (!_creating && selected < 0) return false;
    if (!_creating && _name.text == tags[selected]['name']) {
      setState(() => _naming = false);
      _nameFocus.unfocus();
      return true;
    }
    setState(() => _working = true);
    widget.onStop();
    final creating = _creating;
    final ok = await widget.onEdit(creating ? 'addTag' : 'updateTag', {
      if (!creating) 'index': selected,
      'name': _name.text,
      if (creating) 'from': _from,
      if (creating) 'to': _to,
    });
    if (!mounted) return ok;
    setState(() {
      _working = false;
      if (ok) {
        _creating = false;
        _naming = false;
        _signature = signature;
      }
    });
    if (ok) {
      _nameFocus.unfocus();
      if (creating) widget.onSelected(tags.length - 1);
    }
    return ok;
  }

  Future<void> _selectTag(int index) async {
    if (!await savePending() || !mounted) return;
    widget.onStop();
    _nameFocus.unfocus();
    widget.onSelected(index);
    if (index >= 0) {
      await widget.editor.call('select', {'frame': tags[index]['from']});
    }
  }

  Future<void> _add() async {
    if (count == 0 || !await savePending() || !mounted) return;
    widget.onStop();
    widget.onSelected(-1);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _creating = true;
      _naming = true;
      _name.text = 'Tag';
      _from = widget.editor.frame;
      _to = _from;
    });
    _reveal(_from);
    // Do not open the keyboard until the name is tapped: range handles and the
    // artwork remain visible while extending a newly-created tag.
  }

  void rename() {
    if (blocked || selected < 0 || _creating || _drag != null) return;
    widget.onStop();
    setState(() {
      _naming = true;
      _name.text = tags[selected]['name'] as String;
      _name.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _name.text.length,
      );
    });
    _nameFocus.requestFocus();
  }

  void _cancelName() {
    if (blocked) return;
    _cancelDrag();
    _nameFocus.unfocus();
    setState(_load);
  }

  Future<void> _tapFrame(int frame) async {
    if (blocked || _drag != null) return;
    widget.onStop();
    _nameFocus.unfocus();
    if (hasRange && HardwareKeyboard.instance.isShiftPressed) {
      final anchor = widget.editor.frame;
      await _setRange(
        frame < anchor ? frame : anchor,
        frame > anchor ? frame : anchor,
      );
    }
    await widget.editor.call('select', {'frame': frame});
  }

  Future<void> _setRange(int from, int to) async {
    if (blocked || !hasRange || (_from == from && _to == to)) return;
    final oldFrom = _from, oldTo = _to;
    setState(() {
      _from = from;
      _to = to;
    });
    if (_creating) return;
    setState(() => _working = true);
    final ok = await widget.onEdit('updateTag', {
      'index': selected,
      'from': from,
      'to': to,
    });
    if (!mounted) return;
    setState(() {
      _working = false;
      if (!ok) {
        _from = oldFrom;
        _to = oldTo;
      }
      _signature = signature;
    });
  }

  void _startDrag(bool start, PointerDownEvent event) {
    if (blocked || !hasRange || _drag != null) return;
    widget.onStop();
    _nameFocus.unfocus();
    (start ? _startFocus : _endFocus).requestFocus();
    _drag = _RangeDrag(
      start,
      _from,
      _to,
      event.pointer,
      event.position.dx,
      _frames.offset,
      widget.editor.documentRevision,
    );
    _edgeScroll = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final drag = _drag;
      final box = _stripKey.currentContext?.findRenderObject() as RenderBox?;
      if (drag == null || !drag.moved || box == null || !_frames.hasClients) {
        return;
      }
      final local = box.globalToLocal(Offset(drag.latestX, 0)).dx;
      final delta = local < 36
          ? -12.0
          : local > box.size.width - 36
          ? 12.0
          : 0.0;
      if (delta == 0) return;
      final offset = (_frames.offset + delta).clamp(
        0.0,
        _frames.position.maxScrollExtent,
      );
      if (offset != _frames.offset) {
        _frames.jumpTo(offset);
        _updateDrag(drag.latestX);
      }
    });
  }

  void _updateDrag(double x) {
    final drag = _drag;
    if (drag == null || count == 0) return;
    drag.latestX = x;
    if ((x - drag.x).abs() > 4) drag.moved = true;
    final delta = ((x - drag.x + _frames.offset - drag.offset) / _frameWidth)
        .round();
    setState(() {
      if (drag.start) {
        _from = (drag.from + delta).clamp(0, drag.to);
      } else {
        _to = (drag.to + delta).clamp(drag.from, count - 1);
      }
    });
  }

  void _endDragTimer() {
    _edgeScroll?.cancel();
    _edgeScroll = null;
  }

  void _cancelDrag() {
    final drag = _drag;
    _endDragTimer();
    if (drag == null) return;
    setState(() {
      _from = drag.from;
      _to = drag.to;
      _drag = null;
    });
  }

  Future<void> _finishDrag() async {
    final drag = _drag;
    _endDragTimer();
    if (drag == null) return;
    final from = _from, to = _to;
    _drag = null;
    // Restore the baseline before using the shared single-transaction path.
    _from = drag.from;
    _to = drag.to;
    await _setRange(from, to);
  }

  Future<void> _nudge(bool start, int delta) async {
    if (blocked || _drag != null || !hasRange) return;
    widget.onStop();
    await _setRange(
      start ? (_from + delta).clamp(0, _to) : _from,
      start ? _to : (_to + delta).clamp(_from, count - 1),
    );
    _reveal(start ? _from : _to);
  }

  Future<void> _options(String action) async {
    if (action == 'rename') {
      rename();
      return;
    }
    if (!await savePending() || !mounted) return;
    widget.onStop();
    if (action == 'data') {
      await widget.onData(selected);
    } else if (action == 'playback') {
      await _playbackOptions();
    } else if (action == 'duplicate') {
      if (await widget.onEdit('duplicateTag', {'index': selected}) && mounted) {
        widget.onSelected(tags.length - 1);
      }
    } else if (action == 'delete') {
      if (await widget.onEdit('deleteTag', {'index': selected}) && mounted) {
        widget.onSelected(-1);
      }
    } else if (action == 'undo') {
      await widget.editor.call('undo');
    } else if (action == 'copy') {
      if (await widget.editor.call('copyTag', {'index': selected}) && mounted) {
        _notice('Frames and tag copied. Choose a document, then paste.');
      }
    } else if (action == 'clear') {
      await widget.editor.call('clearTagClipboard');
    } else {
      final ok = await widget.editor.call(
        'pasteTag',
        action == 'new' ? {'asNew': true} : {'after': widget.editor.frame},
      );
      if (ok && mounted) widget.onSelected(tags.length - 1);
    }
  }

  Future<void> _playbackOptions() async {
    final index = selected;
    if (index < 0) return;
    var direction = tags[index]['direction'] as int? ?? 0;
    var repeat = '${tags[index]['repeat'] ?? 0}';
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Tag playback'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  items: [
                    for (final entry in (const {
                      0: 'Forward',
                      1: 'Reverse',
                      2: 'Ping-pong',
                      3: 'Reverse ping-pong',
                    }).entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => update(() => direction = value!),
                ),
                TextFormField(
                  key: const Key('tag-repeat'),
                  initialValue: repeat,
                  onChanged: (value) => repeat = value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repeat (0 = forever)',
                  ),
                  validator: (value) {
                    final n = int.tryParse(value ?? '');
                    return n == null || n < 0 || n > 65535
                        ? 'Enter 0–65535'
                        : null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    final repetitions = int.tryParse(repeat);
    if (result == true && mounted) {
      await widget.onEdit('updateTag', {
        'index': index,
        'direction': direction,
        'repeat': repetitions,
      });
    }
  }

  Widget _tagChip(int index) {
    final name = index < 0 ? 'All frames' : tags[index]['name'] as String;
    final range = index < 0
        ? '$count frames'
        : '${(tags[index]['from'] as int) + 1}–${(tags[index]['to'] as int) + 1}';
    final active = !_creating && selected == index;
    return SizedBox(
      width: _chipWidth(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Tooltip(
          message: '$name · $range',
          child: Semantics(
            selected: active,
            child: TextButton(
              key: Key('tag-chip-$index'),
              onPressed: blocked ? null : () => _selectTag(index),
              onLongPress: active && index >= 0 ? rename : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: active
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    range,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
    height: 48,
    child: Row(
      children: [
        Expanded(
          child: ListView.builder(
            key: const Key('tag-chips'),
            controller: _chips,
            scrollDirection: Axis.horizontal,
            itemCount: tags.length + 1,
            itemBuilder: (_, index) => _tagChip(index - 1),
          ),
        ),
        IconButton(
          key: const Key('add-tag'),
          tooltip: 'Add tag from current frame',
          onPressed: blocked || count == 0 ? null : _add,
          icon: const Icon(Icons.add),
        ),
        PopupMenuButton<String>(
          key: const Key('tag-options'),
          tooltip: 'Tag options',
          enabled: !blocked && _drag == null,
          onSelected: _options,
          itemBuilder: (_) => [
            if (selected >= 0 && !_creating) ...[
              const PopupMenuItem(value: 'rename', child: Text('Rename tag')),
              const PopupMenuItem(
                value: 'duplicate',
                child: Text('Duplicate tag label'),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Text('Copy frames + tag'),
              ),
              const PopupMenuItem(
                value: 'playback',
                child: Text('Direction and repeat…'),
              ),
              const PopupMenuItem(value: 'data', child: Text('User data')),
            ],
            PopupMenuItem(
              value: 'after',
              enabled: widget.editor.state['hasTagClipboard'] == true,
              child: const Text('Paste after current frame'),
            ),
            PopupMenuItem(
              value: 'new',
              enabled: widget.editor.state['hasTagClipboard'] == true,
              child: const Text('Paste as new document'),
            ),
            if (widget.editor.state['hasTagClipboard'] == true)
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear copied tag'),
              ),
            if (widget.editor.canUndo)
              const PopupMenuItem(value: 'undo', child: Text('Undo')),
            if (selected >= 0 && !_creating)
              const PopupMenuItem(value: 'delete', child: Text('Delete tag')),
          ],
        ),
      ],
    ),
  );

  Widget _nameRow() => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('tag-name'),
              controller: _name,
              focusNode: _nameFocus,
              enabled: !blocked,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                labelText: _creating ? 'New tag name' : 'Rename tag',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => savePending(),
            ),
          ),
          TextButton(
            key: const Key('save-tag'),
            onPressed: blocked ? null : savePending,
            child: const Text('Done'),
          ),
          TextButton(
            key: const Key('cancel-tag'),
            onPressed: blocked ? null : _cancelName,
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  int _endpoint(bool start, int delta) => start
      ? (_from + delta).clamp(0, _to)
      : (_to + delta).clamp(_from, count - 1);

  Widget _handle(bool start, double center) => Positioned(
    left: center - 22,
    top: 0,
    width: 44,
    height: 44,
    child: Semantics(
      label: start ? 'Range start' : 'Range end',
      value: '${_endpoint(start, 0) + 1}',
      increasedValue: '${_endpoint(start, 1) + 1}',
      decreasedValue: '${_endpoint(start, -1) + 1}',
      onIncrease: blocked ? null : () => _nudge(start, 1),
      onDecrease: blocked ? null : () => _nudge(start, -1),
      child: Focus(
        focusNode: start ? _startFocus : _endFocus,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nudge(
              start,
              event.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 1,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape && _drag != null) {
            _cancelDrag();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Tooltip(
          message:
              'Drag ${start ? 'start' : 'end'} · frame ${(start ? _from : _to) + 1}',
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Listener(
              key: Key(start ? 'tag-start-handle' : 'tag-end-handle'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _startDrag(start, event),
              onPointerMove: (event) {
                if (_drag?.pointer == event.pointer) {
                  _updateDrag(event.position.dx);
                }
              },
              onPointerUp: (event) {
                if (_drag?.pointer == event.pointer) _finishDrag();
              },
              onPointerCancel: (event) {
                if (_drag?.pointer == event.pointer) _cancelDrag();
              },
              child: Center(
                child: Container(
                  width: 24,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    start ? Icons.chevron_left : Icons.chevron_right,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _strip() => SizedBox(
    key: _stripKey,
    child: AnimatedBuilder(
      animation: _frames,
      builder: (context, _) {
        final offset = _frames.hasClients ? _frames.offset : 0.0;
        final start = _from * _frameWidth + _gutter - offset;
        final end = (_to + 1) * _frameWidth + _gutter - offset;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              top: hasRange ? 44 : 0,
              child: ListView.builder(
                scrollCacheExtent: ScrollCacheExtent.pixels(152),
                key: const Key('tag-frame-strip'),
                controller: _frames,
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                scrollDirection: Axis.horizontal,
                itemExtent: _frameWidth,
                itemCount: count,
                itemBuilder: (context, index) => _FrameCard(
                  editor: widget.editor,
                  frame: index,
                  inRange: hasRange && index >= _from && index <= _to,
                  current: index == widget.editor.frame,
                  start: hasRange && index == _from,
                  end: hasRange && index == _to,
                  onTap: blocked ? null : () => _tapFrame(index),
                ),
              ),
            ),
            if (hasRange) ...[
              Positioned(
                left: start,
                top: 20,
                width: end - start,
                height: 4,
                child: ColoredBox(color: Theme.of(context).colorScheme.primary),
              ),
              Positioned(
                left: start + 22,
                top: 0,
                width: (end - start - 44).clamp(0.0, double.infinity),
                height: 20,
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      '${_from + 1}–${_to + 1}',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
              _handle(true, start),
              _handle(false, end),
            ],
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff1c2331),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Hidden panels stay mounted with zero height to retain pending names.
        if (constraints.maxHeight < 1 || !widget.active) {
          return const SizedBox.shrink();
        }
        final compact = constraints.maxHeight < 200;
        return Column(
          children: [
            if (!_naming || !compact) _header(),
            if (_naming) _nameRow(),
            Expanded(child: _strip()),
          ],
        );
      },
    ),
  );
}

class _RangeDrag {
  _RangeDrag(
    this.start,
    this.from,
    this.to,
    this.pointer,
    this.x,
    this.offset,
    this.revision,
  ) : latestX = x;
  final bool start;
  final int from, to, pointer, revision;
  final double x, offset;
  double latestX;
  bool moved = false;
}

class _FrameCard extends StatefulWidget {
  const _FrameCard({
    required this.editor,
    required this.frame,
    required this.inRange,
    required this.current,
    required this.start,
    required this.end,
    required this.onTap,
  });
  final Editor editor;
  final int frame;
  final bool inRange, current, start, end;
  final VoidCallback? onTap;
  @override
  State<_FrameCard> createState() => _FrameCardState();
}

class _FrameCardState extends State<_FrameCard> {
  ui.Image? _image;
  bool _loading = true;
  int _revision = -1, _request = 0;
  @override
  void initState() {
    super.initState();
    widget.editor.documentChanges.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(_FrameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      oldWidget.editor.documentChanges.removeListener(_changed);
      widget.editor.documentChanges.addListener(_changed);
    }
    if (oldWidget.frame != widget.frame ||
        oldWidget.editor != widget.editor ||
        _revision != widget.editor.documentRevision) {
      _load();
    }
  }

  void _changed() {
    if (_revision != widget.editor.documentRevision) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    _revision = widget.editor.documentRevision;
    // Keep the previous preview visible while its replacement is decoded.
    _loading = _image == null;
    final image = await widget.editor.thumbnail(widget.frame);
    if (!mounted || request != _request) {
      image?.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _request++;
    widget.editor.documentChanges.removeListener(_changed);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        'Frame ${widget.frame + 1}${widget.current ? ', current frame' : ''}${widget.inRange ? ', in selected range' : ''}${widget.start ? ', range start' : ''}${widget.end ? ', range end' : ''}';
    final preview = _image != null
        ? SizedBox.expand(
            child: RawImage(
              image: _image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          )
        : _loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Tooltip(
            message: 'Preview unavailable; tap to open frame',
            child: Icon(Icons.image_not_supported_outlined, size: 18),
          );
    return Semantics(
      label: label,
      button: true,
      selected: widget.current,
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: InkWell(
            key: Key('tag-frame-${widget.frame}'),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                color: widget.inRange
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .6)
                    : const Color(0xff293244),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.current
                      ? Theme.of(context).colorScheme.primary
                      : widget.inRange
                      ? const Color(0xff7c8bbc)
                      : Colors.transparent,
                  width: widget.current ? 3 : 1,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: Column(
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: const _Checker(),
                      child: Center(child: preview),
                    ),
                  ),
                  Text(
                    '${widget.frame + 1}${widget.start ? ' · S' : ''}${widget.end ? ' · E' : ''}',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Checker extends CustomPainter {
  const _Checker();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffa1a6b1),
    );
    for (var y = 0.0; y < size.height; y += 6) {
      for (var x = 0.0; x < size.width; x += 6) {
        if (((x / 6).floor() + (y / 6).floor()).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, 6, 6).intersect(Offset.zero & size),
            Paint()..color = const Color(0xff747c8a),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Checker oldDelegate) => false;
}
