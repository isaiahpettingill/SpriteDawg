import 'package:flutter/material.dart';

/// A slanted two-tone block eraser, intentionally unlike a magic wand.
class EraserIcon extends StatelessWidget {
  const EraserIcon({super.key, this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _EraserPainter(IconTheme.of(context).color ?? Colors.white),
  );
}

class _EraserPainter extends CustomPainter {
  const _EraserPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final outline = Path()
      ..moveTo(3, 14)
      ..lineTo(12, 4)
      ..quadraticBezierTo(13, 3, 14, 4)
      ..lineTo(21, 10)
      ..quadraticBezierTo(22, 11, 21, 12)
      ..lineTo(13, 21)
      ..lineTo(9, 21)
      ..close();
    canvas.drawPath(
      outline,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
    final cap = Path()
      ..moveTo(3, 14)
      ..lineTo(8, 9)
      ..lineTo(16, 16)
      ..lineTo(13, 21)
      ..lineTo(9, 21)
      ..close();
    canvas.drawPath(cap, Paint()..color = color);
    canvas.drawLine(
      const Offset(14, 21),
      const Offset(22, 21),
      Paint()
        ..color = color
        ..strokeWidth = 1.8,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EraserPainter oldDelegate) => oldDelegate.color != color;
}
