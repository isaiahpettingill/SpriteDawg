import 'package:flutter/material.dart';

Future<(int, int)?> showNewCanvasDialog(
  BuildContext context, {
  required int width,
  required int height,
}) => showDialog<(int, int)>(
  context: context,
  builder: (_) => _NewCanvasDialog(width: width, height: height),
);

class _NewCanvasDialog extends StatefulWidget {
  const _NewCanvasDialog({required this.width, required this.height});
  final int width, height;

  @override
  State<_NewCanvasDialog> createState() => _NewCanvasDialogState();
}

class _NewCanvasDialogState extends State<_NewCanvasDialog> {
  final _form = GlobalKey<FormState>();
  late final _width = TextEditingController(text: '${widget.width}');
  late final _height = TextEditingController(text: '${widget.height}');

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final n = int.tryParse(value?.trim() ?? '');
    return n == null || n < 1 || n > 2048 ? 'Enter 1–2048 pixels' : null;
  }

  void _create() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (
      int.parse(_width.text.trim()),
      int.parse(_height.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New canvas'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('new-canvas-width'),
              controller: _width,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Width', suffixText: 'px'),
              validator: _validate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('new-canvas-height'),
              controller: _height,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Height', suffixText: 'px'),
              validator: _validate,
              onFieldSubmitted: (_) => _create(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _create, child: const Text('Create')),
    ],
  );
}
