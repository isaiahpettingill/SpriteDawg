import 'package:flutter/material.dart';

/// A visual HSV picker shared by brush and palette editing. Values remain ARGB,
/// including hidden RGB at zero alpha; opening/cancelling never edits a document.
Future<int?> showSpriteColorPicker(
  BuildContext context, {
  required int initialColor,
  String title = 'Brush color',
}) => showDialog<int>(
  context: context,
  builder: (_) => _ColorPickerDialog(initialColor: initialColor, title: title),
);

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialColor, required this.title});
  final int initialColor;
  final String title;
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int color = widget.initialColor;
  bool valid = true;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: SpriteColorPicker(
          initialColor: color,
          onChanged: (value) => color = value,
          onValidityChanged: (value) => setState(() => valid = value),
          onSubmitted: () {
            if (valid) Navigator.pop(context, color);
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: valid ? () => Navigator.pop(context, color) : null,
        child: const Text('Use color'),
      ),
    ],
  );
}

class SpriteColorPicker extends StatefulWidget {
  const SpriteColorPicker({
    super.key,
    required this.initialColor,
    required this.onChanged,
    this.onValidityChanged,
    this.onSubmitted,
  });
  final int initialColor;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool>? onValidityChanged;
  final VoidCallback? onSubmitted;
  @override
  State<SpriteColorPicker> createState() => _SpriteColorPickerState();
}

class _SpriteColorPickerState extends State<SpriteColorPicker> {
  late HSVColor hsv = HSVColor.fromColor(Color(widget.initialColor));
  late final TextEditingController hex = TextEditingController(
    text: _hex(widget.initialColor),
  );
  String? error;
  String _hex(int color) =>
      color.toRadixString(16).padLeft(8, '0').toUpperCase();
  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void _set(HSVColor value) {
    setState(() {
      hsv = value;
      error = null;
      hex.text = _hex(hsv.toColor().toARGB32());
    });
    widget.onValidityChanged?.call(true);
    widget.onChanged(hsv.toColor().toARGB32());
  }

  void _fromHex(String raw) {
    final value = raw.trim().replaceFirst('#', '');
    final valid = RegExp(
      r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
    ).hasMatch(value);
    setState(() {
      error = valid ? null : 'Use RRGGBB or AARRGGBB';
      if (valid) {
        final color = int.parse(
          value.length == 6 ? 'FF$value' : value,
          radix: 16,
        );
        final next = HSVColor.fromColor(Color(color));
        // Keep the selected hue while moving through gray or black.
        hsv = next.saturation == 0 ? next.withHue(hsv.hue) : next;
        widget.onChanged(color);
      }
    });
    widget.onValidityChanged?.call(valid);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: 'Saturation and brightness',
        hint: 'Drag right for more saturation, up for more brightness',
        child: SizedBox(
          height: 180,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(Offset point) => _set(
                hsv
                    .withSaturation(
                      (point.dx / constraints.maxWidth).clamp(0.0, 1.0),
                    )
                    .withValue((1 - point.dy / 180).clamp(0.0, 1.0)),
              );
              return GestureDetector(
                key: const Key('color-saturation-value'),
                behavior: HitTestBehavior.opaque,
                onPanDown: (event) => update(event.localPosition),
                onPanUpdate: (event) => update(event.localPosition),
                child: CustomPaint(painter: _SaturationValuePainter(hsv)),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      _slider(
        'Hue',
        hsv.hue,
        360,
        (v) => _set(hsv.withHue(v)),
        gradient: const LinearGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Color(0xff00ff00),
            Colors.cyan,
            Colors.blue,
            Color(0xffff00ff),
            Colors.red,
          ],
        ),
      ),
      // Individual controls supplement the two-dimensional pad for keyboard
      // and screen-reader users.
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Saturation / brightness'),
        children: [
          _slider(
            'Saturation',
            hsv.saturation,
            1,
            (v) => _set(hsv.withSaturation(v)),
          ),
          _slider('Brightness', hsv.value, 1, (v) => _set(hsv.withValue(v))),
        ],
      ),
      _slider(
        'Opacity',
        hsv.alpha,
        1,
        (v) => _set(hsv.withAlpha(v)),
        gradient: LinearGradient(
          colors: [hsv.withAlpha(0).toColor(), hsv.withAlpha(1).toColor()],
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 36,
        child: CustomPaint(
          painter: const ColorCheckerPainter(),
          child: ColoredBox(color: hsv.toColor()),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('color-hex'),
        controller: hex,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Hex · AARRGGBB / RRGGBB',
          prefixText: '#',
          errorText: error,
        ),
        onChanged: _fromHex,
        onSubmitted: (_) {
          if (error == null) widget.onSubmitted?.call();
        },
      ),
    ],
  );

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> change, {
    Gradient? gradient,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label · ${max == 360 ? '${value.round()}°' : '${(value * 100).round()}%'}',
      ),
      CustomPaint(
        painter: gradient == null ? null : const ColorCheckerPainter(),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: Slider(
            key: Key('color-${label.toLowerCase()}'),
            semanticFormatterCallback: (v) => max == 360
                ? '${v.round()} degrees'
                : '${(v * 100).round()} percent',
            label: label,
            value: value,
            min: 0,
            max: max,
            onChanged: change,
          ),
        ),
      ),
    ],
  );
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            hsv.withSaturation(1).withValue(1).withAlpha(1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final point = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hsv != hsv;
}

class ColorCheckerPainter extends CustomPainter {
  const ColorCheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffeeeeee),
    );
    final dark = Paint()..color = const Color(0xffaaaaaa);
    for (var y = 0; y < size.height; y += 8) {
      for (var x = 0; x < size.width; x += 8) {
        if ((x ~/ 8 + y ~/ 8).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              (size.width - x).clamp(0, 8).toDouble(),
              (size.height - y).clamp(0, 8).toDouble(),
            ),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(ColorCheckerPainter old) => false;
}
