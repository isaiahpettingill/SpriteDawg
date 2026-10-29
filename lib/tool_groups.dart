import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'eraser_icon.dart';

class DrawingSubtool {
  const DrawingSubtool(this.id, this.label, this.icon);
  final String id, label;
  final IconData icon;
}

const drawingToolGroups = <String, List<DrawingSubtool>>{
  'ink': [
    DrawingSubtool('pencil', 'Pencil', Icons.edit),
    DrawingSubtool('spray', 'Spray', Icons.grain),
    DrawingSubtool('splatter', 'Splatter', Icons.bubble_chart),
    DrawingSubtool('airbrush', 'Airbrush', Icons.blur_circular),
    DrawingSubtool('ditherPaint', 'Dither Paint', Icons.gradient),
  ],
  'texture': [
    DrawingSubtool('metal', 'Metal', Icons.brightness_medium),
    DrawingSubtool('cluster', 'Cluster', Icons.grain),
    DrawingSubtool('stripes', 'Stripes', Icons.texture),
    DrawingSubtool('sphere', 'Sphere', Icons.circle),
    DrawingSubtool('knife', 'Knife', Icons.architecture),
    DrawingSubtool('bark', 'Bark', Icons.forest),
    DrawingSubtool('leaves', 'Leaves', Icons.eco),
  ],
  'eraser': [DrawingSubtool('eraser', 'Eraser', Icons.auto_fix_normal)],
  'fill': [
    DrawingSubtool('fill', 'Fill', Icons.format_color_fill),
    DrawingSubtool('gradient', 'Gradient', Icons.gradient),
  ],
  'sample': [DrawingSubtool('eyedropper', 'Eyedropper', Icons.colorize)],
  'shape': [
    DrawingSubtool('line', 'Line', Icons.show_chart),
    DrawingSubtool('rectangle', 'Rectangle', Icons.crop_square),
    DrawingSubtool('rectangleFilled', 'Filled rectangle', Icons.square),
    DrawingSubtool('ellipse', 'Ellipse', Icons.circle_outlined),
    DrawingSubtool('ellipseFilled', 'Filled ellipse', Icons.circle),
  ],
  'effect': [
    DrawingSubtool('blur', 'Blur', Icons.blur_on),
    DrawingSubtool('jumble', 'Jumble', Icons.shuffle),
    DrawingSubtool('ditherRetouch', 'Dither Retouch', Icons.grid_4x4),
  ],
  'select': [DrawingSubtool('selectRegion', 'Select', Icons.select_all)],
};

/// A tap chooses the remembered tool; hold/right-click/Menu key opens choices.
/// State is owned above the responsive layouts so rotating never resets groups.
class DrawingToolGroupButton extends StatelessWidget {
  const DrawingToolGroupButton({
    super.key,
    required this.group,
    required this.current,
    required this.active,
    required this.onSelected,
  });
  final String group, current;
  final bool active;
  final ValueChanged<String> onSelected;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      semanticLabel: 'Choose subtool',
      items: [
        for (final item in drawingToolGroups[group]!)
          PopupMenuItem(
            value: item.id,
            child: Row(
              children: [
                Icon(item.icon),
                const SizedBox(width: 12),
                Expanded(child: Text(item.label)),
                if (current == item.id) const Icon(Icons.check),
              ],
            ),
          ),
      ],
    );
    if (choice != null) onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final items = drawingToolGroups[group]!;
    final item = items.firstWhere(
      (e) => e.id == current,
      orElse: () => items.first,
    );
    final hasChoices = items.length > 1;
    final help = item.id == 'splatter'
        ? 'Splatter: variable alpha in RGB; exact palette alpha in indexed mode'
        : item.label;
    return Builder(
      builder: (buttonContext) => Semantics(
        label: item.label,
        hint: hasChoices ? 'Long press to choose subtool' : null,
        button: true,
        selected: active,
        onLongPress: hasChoices ? () => _open(buttonContext) : null,
        child: Tooltip(
          message: help,
          triggerMode: TooltipTriggerMode.manual,
          child: GestureDetector(
            onLongPress: hasChoices ? () => _open(buttonContext) : null,
            onSecondaryTap: hasChoices ? () => _open(buttonContext) : null,
            child: Focus(
              onKeyEvent: (_, event) {
                if (hasChoices &&
                    event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                        (event.logicalKey == LogicalKeyboardKey.f10 &&
                            HardwareKeyboard.instance.isShiftPressed))) {
                  _open(buttonContext);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filledTonal(
                  key: Key('tool-group-$group'),
                  isSelected: active,
                  onPressed: () => onSelected(item.id),
                  style: IconButton.styleFrom(
                    backgroundColor: active
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                  ),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      item.id == 'eraser'
                          ? const EraserIcon()
                          : Icon(item.icon),
                      if (hasChoices)
                        const Positioned(
                          right: -5,
                          bottom: -5,
                          child: Icon(Icons.arrow_drop_down, size: 13),
                        ),
                    ],
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
