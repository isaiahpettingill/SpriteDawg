import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'editor.dart';

enum _RangeTarget { browse, start, end }

/// Aseprite tags remain ordinary named ranges: browsing tiles and playing an
/// animation are viewer actions, never new file types or automatic renames.
class VisualTagEditor extends StatefulWidget {
  const VisualTagEditor({
    super.key,
    required this.editor,
    required this.selectedTag,
    required this.playing,
    required this.onSelected,
    required this.onEdit,
    required this.onPlay,
    required this.onStop,
    required this.onData,
    required this.onEditingChanged,
  });
  final Editor editor;
  final int selectedTag;
  final bool playing;
  final ValueChanged<int> onSelected;
  final Future<bool> Function(String, Map<String, dynamic>) onEdit;
  final VoidCallback onPlay, onStop;
  final Future<void> Function(int) onData;
  final ValueChanged<bool> onEditingChanged;
  @override
  State<VisualTagEditor> createState() => VisualTagEditorState();
}

class VisualTagEditorState extends State<VisualTagEditor> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _frames = ScrollController();
  bool _creating = false, _dirty = false, _working = false;
  int _from = 0, _to = 0;
  String _signature = '';
  _RangeTarget _target = _RangeTarget.browse;
  Object? _tagSource;
  List<Map<String, dynamic>> _cachedTags = [];
  List<Map<String, dynamic>> get tags {
    final source = widget.editor.state['tags'];
    if (!identical(source, _tagSource)) {
      _tagSource = source;
      _cachedTags = (source as List? ?? const [])
          .map((tag) => Map<String, dynamic>.from(tag as Map))
          .toList();
    }
    return _cachedTags;
  }

  int get count => (widget.editor.state['frames'] as List? ?? const []).length;
  int get selected =>
      widget.selectedTag >= 0 && widget.selectedTag < tags.length
      ? widget.selectedTag
      : -1;
  bool get editing => _creating || selected >= 0;
  bool get blocked => widget.editor.busy || _working;
  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => widget.onEditingChanged(_nameFocus.hasFocus));
    _load();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(widget.editor.frame),
    );
  }

  String get signature => selected < 0
      ? ''
      : '${tags[selected]['name']}\u0000${tags[selected]['from']}:${tags[selected]['to']}';
  void _load() {
    _creating = false;
    _dirty = false;
    _target = _RangeTarget.browse;
    if (selected >= 0) {
      final tag = tags[selected];
      _name.text = tag['name'] as String;
      _from = tag['from'] as int;
      _to = tag['to'] as int;
    } else {
      _name.text = '';
      _from = 0;
      _to = (count - 1).clamp(0, 4095);
    }
    _signature = signature;
  }

  int _lastFrame = -1;
  @override
  void didUpdateWidget(VisualTagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTag != widget.selectedTag ||
        (!_dirty && !_creating && _signature != signature)) {
      _load();
    }
    if (_lastFrame != widget.editor.frame) {
      _lastFrame = widget.editor.frame;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_lastFrame));
    }
    if (_from >= count || _to >= count) {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _frames.dispose();
    super.dispose();
  }

  void _reveal(int frame) {
    if (!mounted || !_frames.hasClients) return;
    final left = frame * 76.0;
    final viewport = _frames.position.viewportDimension;
    if (left < _frames.offset || left + 76 > _frames.offset + viewport) {
      _frames.jumpTo(
        (left - viewport / 2 + 38).clamp(0.0, _frames.position.maxScrollExtent),
      );
    }
  }

  void _notice(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
  Future<bool> savePending() => _save();
  Future<bool> _save() async {
    if (!editing || !_dirty) return true;
    if (blocked) return false;
    if (_name.text.trim().isEmpty) {
      _notice('Give this tag a name.');
      _nameFocus.requestFocus();
      return false;
    }
    setState(() => _working = true);
    widget.onStop();
    final index = selected;
    final wasCreating = _creating;
    final ok = await widget.onEdit(wasCreating ? 'addTag' : 'updateTag', {
      if (!wasCreating) 'index': index,
      'name': _name.text,
      'from': _from,
      'to': _to,
    });
    if (!mounted) return ok;
    setState(() => _working = false);
    if (ok) {
      _dirty = false;
      _creating = false;
      if (wasCreating) widget.onSelected(tags.length - 1);
      _signature = signature;
      _nameFocus.unfocus();
    }
    return ok;
  }

  Future<void> _selectTag(int index) async {
    if (blocked || !await _save()) return;
    widget.onStop();
    _nameFocus.unfocus();
    setState(() => _creating = false);
    widget.onSelected(index);
    if (index >= 0) {
      await widget.editor.call('select', {'frame': tags[index]['from']});
    }
  }

  Future<void> _add() async {
    if (blocked || !await _save()) return;
    widget.onStop();
    widget.onSelected(-1);
    // onSelected updates the parent synchronously; create after its rebuild so
    // didUpdateWidget cannot reset this new draft.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _creating = true;
      _dirty = true;
      _name.text = 'Tag';
      _from = widget.editor.frame;
      _to = _from;
      _target = _RangeTarget.end;
    });
    _reveal(_from);
  }

  Future<void> _tapFrame(int frame) async {
    if (blocked) return;
    widget.onStop();
    _nameFocus.unfocus();
    if (editing && _target != _RangeTarget.browse) {
      setState(() {
        if (_target == _RangeTarget.start) {
          _from = frame;
          if (_to < _from) _to = _from;
        } else {
          _to = frame;
          if (_from > _to) _from = _to;
        }
        _dirty = true;
      });
    }
    await widget.editor.call('select', {'frame': frame});
  }

  Future<void> _step(int delta) async {
    if (blocked || count == 0) return;
    widget.onStop();
    _target = _RangeTarget.browse;
    final from = editing ? _from : 0, to = editing ? _to : count - 1;
    final current = widget.editor.frame;
    final next = delta > 0
        ? (current < from || current >= to ? from : current + 1)
        : (current <= from || current > to ? to : current - 1);
    await _tapFrame(next);
  }

  Future<void> _duplicate() async {
    if (blocked || selected < 0 || !await _save()) return;
    final index = selected;
    if (await widget.onEdit('duplicateTag', {'index': index}) && mounted) {
      widget.onSelected(tags.length - 1);
    }
  }

  Widget _tagChip(int index, String name, String range) {
    final active = !_creating && selected == index;
    return Semantics(
      button: true,
      selected: active,
      label: '$name, $range',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 48,
          width: index < 0 ? 94 : 148,
          child: TextButton(
            onPressed: blocked ? null : () => _selectTag(index),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: active
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(range, style: const TextStyle(fontSize: 10), maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
    Key? key,
  }) => SizedBox(
    height: 48,
    child: TextButton.icon(
      key: key,
      onPressed: action,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final canStep = count > 1 && (!editing || _to > _from);
    return Material(
      color: const Color(0xff1c2331),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four compact rows fit a 320px-high landscape phone after app chrome.
          const rowHeight = 48.0;
          final rows = <Widget>[
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: tags.length + 1,
                      itemBuilder: (context, item) {
                        if (item == 0) {
                          return _tagChip(-1, 'All frames', '$count frames');
                        }
                        final i = item - 1;
                        return _tagChip(
                          i,
                          tags[i]['name'] as String,
                          '${(tags[i]['from'] as int) + 1}–${(tags[i]['to'] as int) + 1}',
                        );
                      },
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Copy or paste tagged section',
                    enabled: !blocked,
                    icon: const Icon(Icons.content_paste),
                    onSelected: (action) async {
                      if (!await _save() || !mounted) return;
                      widget.onStop();
                      if (action == 'copy') {
                        final copied = await widget.editor.call('copyTag', {
                          'index': selected,
                        });
                        if (copied && mounted) {
                          _notice(
                            'Tagged frames copied. Choose a document, then paste.',
                          );
                        }
                      } else if (action == 'clear') {
                        await widget.editor.call('clearTagClipboard');
                      } else {
                        final ok = await widget.editor.call(
                          'pasteTag',
                          action == 'new'
                              ? {'asNew': true}
                              : {'after': widget.editor.frame},
                        );
                        if (ok && mounted) widget.onSelected(tags.length - 1);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'copy',
                        enabled: selected >= 0 && !_creating,
                        child: const Text('Copy tagged section'),
                      ),
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
                      PopupMenuItem(
                        value: 'clear',
                        enabled: widget.editor.state['hasTagClipboard'] == true,
                        child: const Text('Clear copied tag'),
                      ),
                    ],
                  ),
                  IconButton(
                    key: const Key('add-tag'),
                    tooltip: 'Add tag from current frame',
                    onPressed: blocked ? null : _add,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: editing
                          ? TextField(
                              key: const Key('tag-name'),
                              controller: _name,
                              focusNode: _nameFocus,
                              enabled: !blocked,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: _creating
                                    ? 'New tag name'
                                    : 'Tag name',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() => _dirty = true),
                              onSubmitted: (_) => _save(),
                            )
                          : const Text(
                              'Choose a tag, or add one.\nTags can group tiles or animation frames.',
                              style: TextStyle(fontSize: 12),
                            ),
                    ),
                    if (editing)
                      IconButton(
                        key: const Key('save-tag'),
                        tooltip: _creating
                            ? 'Create tag'
                            : _dirty
                            ? 'Save tag changes'
                            : 'Tag saved',
                        onPressed: blocked || !_dirty ? null : _save,
                        icon: Icon(_dirty ? Icons.check_circle : Icons.check),
                      ),
                    if (selected >= 0 && !_creating)
                      IconButton(
                        key: const Key('duplicate-tag'),
                        tooltip: 'Duplicate tag, preserving metadata',
                        onPressed: blocked ? null : _duplicate,
                        icon: const Icon(Icons.copy),
                      ),
                    if (selected >= 0 && !_creating)
                      PopupMenuButton<String>(
                        tooltip: 'Tag options',
                        enabled: !blocked,
                        onSelected: (action) async {
                          if (!await _save() || !mounted) return;
                          if (action == 'data') {
                            await widget.onData(selected);
                          } else if (action == 'undo') {
                            widget.onStop();
                            await widget.editor.call('undo');
                          } else if (action == 'delete') {
                            if (await widget.onEdit('deleteTag', {
                                  'index': selected,
                                }) &&
                                mounted) {
                              widget.onSelected(-1);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'data',
                            child: Text('User data'),
                          ),
                          if (widget.editor.canUndo)
                            const PopupMenuItem(
                              value: 'undo',
                              child: Text('Undo'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete tag'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: rowHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _control(
                      'Browse',
                      Icons.touch_app,
                      blocked
                          ? null
                          : () {
                              widget.onStop();
                              setState(() => _target = _RangeTarget.browse);
                            },
                      selected:
                          _target == _RangeTarget.browse && !widget.playing,
                      key: const Key('browse-tag'),
                    ),
                    if (editing)
                      _control(
                        'Start ${_from + 1}',
                        Icons.first_page,
                        blocked
                            ? null
                            : () {
                                widget.onStop();
                                setState(() => _target = _RangeTarget.start);
                              },
                        selected: _target == _RangeTarget.start,
                        key: const Key('tag-start'),
                      ),
                    if (editing)
                      _control(
                        'End ${_to + 1}',
                        Icons.last_page,
                        blocked
                            ? null
                            : () {
                                widget.onStop();
                                setState(() => _target = _RangeTarget.end);
                              },
                        selected: _target == _RangeTarget.end,
                        key: const Key('tag-end'),
                      ),
                    IconButton(
                      tooltip: 'Previous frame in range',
                      onPressed: blocked || !canStep ? null : () => _step(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Next frame in range',
                      onPressed: blocked || !canStep ? null : () => _step(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    _control(
                      widget.playing ? 'Stop' : 'Play range',
                      widget.playing ? Icons.pause_circle : Icons.play_circle,
                      blocked || !canStep
                          ? null
                          : () async {
                              if (widget.playing) {
                                widget.onStop();
                              } else if (await _save()) {
                                widget.onPlay();
                              }
                            },
                      selected: widget.playing,
                      key: const Key('play-tag'),
                    ),
                  ],
                ),
              ),
            ),
          ];
          final strip = Semantics(
            label: _target == _RangeTarget.start
                ? 'Tap a frame to set the range start'
                : _target == _RangeTarget.end
                ? 'Tap a frame to set the range end'
                : 'Browse frames; selected range is highlighted',
            child: ListView.builder(
              scrollCacheExtent: ScrollCacheExtent.pixels(152),
              key: const Key('tag-frame-strip'),
              controller: _frames,
              scrollDirection: Axis.horizontal,
              itemExtent: 76,
              itemCount: count,
              itemBuilder: (context, index) => _FrameCard(
                editor: widget.editor,
                frame: index,
                inRange: editing && index >= _from && index <= _to,
                current: index == widget.editor.frame,
                start: editing && index == _from,
                end: editing && index == _to,
                onTap: blocked ? null : () => _tapFrame(index),
              ),
            ),
          );
          if (constraints.maxHeight < 208) {
            final previewHeight = (constraints.maxHeight * .4).clamp(
              40.0,
              72.0,
            );
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(child: Column(children: rows)),
                ),
                SizedBox(height: previewHeight, child: strip),
              ],
            );
          }
          return Column(
            children: [
              ...rows,
              Expanded(child: strip),
            ],
          );
        },
      ),
    );
  }
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
    _load();
  }

  @override
  void didUpdateWidget(_FrameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame != widget.frame ||
        oldWidget.editor != widget.editor ||
        _revision != widget.editor.documentRevision) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    _revision = widget.editor.documentRevision;
    _image?.dispose();
    _image = null;
    _loading = true;
    final image = await widget.editor.thumbnail(widget.frame);
    if (!mounted || request != _request) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _request++;
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
