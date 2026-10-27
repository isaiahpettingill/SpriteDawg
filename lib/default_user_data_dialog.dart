import 'package:flutter/material.dart';
import 'default_user_data_store.dart';

Future<void> showDefaultUserDataDialog(
  BuildContext context,
  DefaultUserDataStore store,
) => showDialog<void>(context: context, builder: (_) => _DefaultsDialog(store));

class _DefaultsDialog extends StatefulWidget {
  const _DefaultsDialog(this.store);
  final DefaultUserDataStore store;
  @override
  State<_DefaultsDialog> createState() => _DefaultsDialogState();
}

class _DefaultsDialogState extends State<_DefaultsDialog> {
  final text = TextEditingController();
  bool loading = true, saving = false, unreadable = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      text.text = await widget.store.load();
    } catch (_) {
      unreadable = true;
      error = 'Saved defaults could not be read.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (unreadable) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace unreadable defaults?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.save(text.text);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Default user data'),
    content: SizedBox(
      width: 420,
      child: loading
          ? const LinearProgressIndicator()
          : SingleChildScrollView(
              child: TextField(
                key: const Key('default-user-data-text'),
                controller: text,
                enabled: !saving,
                minLines: 4,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: 'New sprites',
                  hintText: 'credits="..."\nlicense="..."',
                  errorText: error,
                  errorMaxLines: 3,
                ),
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: loading || saving ? null : save,
        child: const Text('Save'),
      ),
    ],
  );
}
