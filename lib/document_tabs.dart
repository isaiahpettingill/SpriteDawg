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
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Close ${doc['title'] ?? 'document'}?'),
          content: const Text(
            'This document has unsaved changes. Cancel to save it first, or explicitly discard its changes and recovery.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and close'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    final ok = await editor.call('closeDocument', {
      'id': doc['id'],
      if (dirty) 'discard': true,
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
