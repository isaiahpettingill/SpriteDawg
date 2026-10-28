import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A drawing modifier, not a tool: opening or changing this menu never replaces
/// the active brush. The badge remains visible when the menu is closed.
class MirroringButton extends StatelessWidget {
  const MirroringButton({
    super.key,
    required this.mirrorX,
    required this.mirrorY,
    required this.mirrorDiagonal,
    required this.mirrorAntiDiagonal,
    required this.onToggle,
    this.ignored = false,
  });

  final bool mirrorX, mirrorY, mirrorDiagonal, mirrorAntiDiagonal, ignored;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final choices = [
      ('x', 'Horizontal', mirrorX, 0.0),
      ('y', 'Vertical', mirrorY, math.pi / 2),
      ('diagonal', 'Diagonal ↘', mirrorDiagonal, math.pi / 4),
      ('antiDiagonal', 'Diagonal ↗', mirrorAntiDiagonal, -math.pi / 4),
    ];
    final active = choices.where((choice) => choice.$3).toList();
    final summary = active.isEmpty
        ? 'Off'
        : active.map((choice) => choice.$2).join(', ');
    return Semantics(
      label: 'Mirroring: $summary',
      selected: active.isNotEmpty,
      child: PopupMenuButton<String>(
        key: const Key('mirroring-menu'),
        tooltip: 'Mirroring',
        onSelected: onToggle,
        icon: Badge(
          key: const Key('mirroring-status'),
          isLabelVisible: active.isNotEmpty,
          label: Text('${active.length}'),
          child: Icon(
            Icons.flip,
            color: active.isEmpty
                ? null
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        itemBuilder: (_) => [
          for (final choice in choices)
            CheckedPopupMenuItem(
              key: Key('mirror-${choice.$1}'),
              value: choice.$1,
              checked: choice.$3,
              child: Row(
                children: [
                  Transform.rotate(
                    angle: choice.$4,
                    child: const Icon(Icons.swap_horiz, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(choice.$2),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'off',
            enabled: active.isNotEmpty,
            child: const Text('Turn off'),
          ),
          if (ignored)
            const PopupMenuItem(
              enabled: false,
              child: Text('Gradient ignores mirroring'),
            ),
        ],
      ),
    );
  }
}
