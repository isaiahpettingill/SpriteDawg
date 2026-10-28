import 'package:flutter/material.dart';
import 'editor.dart';

class DocumentTabs extends StatelessWidget {
  const DocumentTabs({
    super.key,
    required this.editor,
    required this.onNew,
    required this.onOpen,
    required this.beforeSwitch,
  });
  final Editor editor;
  final VoidCallback onNew, onOpen;
  final Future<bool> Function() beforeSwitch;
  Future<void> _close(BuildContext context, Map<String, dynamic> doc) async {
    if (!await beforeSwitch() || !context.mounted) return;
    final refreshed = editor
        .maps('documents')
        .where((d) => d['id'] == doc['id'])
        .firstOrNull;
    if (refreshed == null) return;
    final dirty = refreshed['dirty'] == true;
    String? choice;
    if (dirty) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Close ${doc['title'] ?? 'document'}?'),
          content: const Text(
            'Keep an internal draft to continue later, or permanently discard the unsaved changes. Original files are not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('Keep draft and close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard and close'),
            ),
          ],
        ),
      );
      if (choice != 'discard' && choice != 'keep') return;
    }
    final ok = await editor.call('closeDocument', {
      'id': doc['id'],
      if (choice == 'discard') 'discard': true,
      if (choice == 'keep') 'keepDraft': true,
    });
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editor.error ?? 'Could not close document')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = editor.maps('documents');
    return Material(
      color: const Color(0xff171d29),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final active = doc['active'] == true;
                final title =
                    '${doc['title'] ?? 'Untitled'}${doc['dirty'] == true ? ' •' : ''}';
                return Semantics(
                  selected: active,
                  label: '$title document',
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 120,
                      maxWidth: 220,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: TextButton(
                            onPressed: editor.busy
                                ? null
                                : () async {
                                    if (!await beforeSwitch()) return;
                                    final ok = await editor.call(
                                      'selectDocument',
                                      {'id': doc['id']},
                                    );
                                    if (!ok && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            editor.error ??
                                                'Could not switch document',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close ${doc['title'] ?? 'document'}',
                          onPressed: editor.busy
                              ? null
                              : () => _close(context, doc),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New document tab',
            onPressed: editor.busy ? null : onNew,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Open document tab',
            onPressed: editor.busy ? null : onOpen,
            icon: const Icon(Icons.folder_open),
          ),
        ],
      ),
    );
  }
}
