import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact, lazy frame strip. Timing stays in frame options, not on every card.
class FramePanel extends StatefulWidget {
  const FramePanel({
    super.key,
    required this.frame,
    required this.durations,
    required this.documentId,
    required this.busy,
    required this.onSelect,
    required this.onDuration,
    required this.onAdd,
    required this.onDuplicate,
    required this.onDelete,
  });

  final int frame;
  final List<int> durations;
  final Object? documentId;
  final bool busy;
  final ValueChanged<int> onSelect, onDuration;
  final VoidCallback onAdd, onDuplicate, onDelete;

  @override
  State<FramePanel> createState() => _FramePanelState();
}

class _FramePanelState extends State<FramePanel> {
  static const _cardWidth = 84.0, _itemExtent = 92.0, _padding = 12.0;
  final _scroll = ScrollController(keepScrollOffset: false);
  double? _viewportWidth;
  bool _revealScheduled = false;

  @override
  void didUpdateWidget(FramePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame != widget.frame ||
        oldWidget.documentId != widget.documentId ||
        oldWidget.durations.length != widget.durations.length) {
      _scheduleReveal();
    }
  }

  // Reveal only on navigation/geometry changes, never on ordinary editor updates.
  // Fixed item extents reach unbuilt cards without relying on a GlobalKey/context.
  void _scheduleReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_scroll.hasClients || widget.durations.isEmpty) return;
      final position = _scroll.position;
      if (!position.hasContentDimensions) return;
      final index = widget.frame.clamp(0, widget.durations.length - 1).toInt();
      final start = _padding + index * _itemExtent;
      final end = start + _cardWidth;
      var target = position.pixels;
      if (start < target + _padding) {
        target = start - _padding;
      } else if (end > target + position.viewportDimension - _padding) {
        target = end + _padding - position.viewportDimension;
      }
      target = target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() > 0.5) _scroll.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff1c2331),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Frame ${widget.frame + 1} / ${widget.durations.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Add blank frame',
              onPressed: widget.busy ? null : widget.onAdd,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Duplicate frame',
              onPressed: widget.busy ? null : widget.onDuplicate,
              icon: const Icon(Icons.copy),
            ),
            PopupMenuButton<String>(
              tooltip: 'Frame options',
              enabled: !widget.busy && widget.durations.isNotEmpty,
              onSelected: (value) {
                if (value == 'duration') widget.onDuration(widget.frame);
                if (value == 'delete') widget.onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'duration', child: Text('Duration…')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: widget.durations.length > 1,
                  child: const Text('Delete frame'),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_viewportWidth != constraints.maxWidth) {
                _viewportWidth = constraints.maxWidth;
                _scheduleReveal();
              }
              return ListView.builder(
                key: const Key('frame-strip'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(_padding),
                itemExtent: _itemExtent,
                itemCount: widget.durations.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _card(context, index),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _card(BuildContext context, int index) {
    final selected = index == widget.frame;
    void duration() => widget.onDuration(index);
    return Semantics(
      key: Key('frame-card-$index'),
      label: 'Frame ${index + 1}',
      value: '${widget.durations[index]} milliseconds',
      hint: 'Long press to edit duration',
      button: true,
      selected: selected,
      enabled: !widget.busy,
      onTap: widget.busy ? null : () => widget.onSelect(index),
      onLongPress: widget.busy ? null : duration,
      excludeSemantics: true,
      child: GestureDetector(
        onSecondaryTap: widget.busy ? null : duration,
        child: Focus(
          onKeyEvent: (_, event) {
            if (!widget.busy &&
                event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                    (event.logicalKey == LogicalKeyboardKey.f10 &&
                        HardwareKeyboard.instance.isShiftPressed))) {
              duration();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: InkWell(
            onTap: widget.busy ? null : () => widget.onSelect(index),
            onLongPress: widget.busy ? null : duration,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              width: _cardWidth,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : const Color(0xff293244),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
