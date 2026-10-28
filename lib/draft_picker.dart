import 'package:flutter/material.dart';

import 'editor.dart';

/// Closing this picker keeps every draft. Destruction is individual and explicit.
Future<void> showDraftPicker(BuildContext context, Editor editor) async {
  await editor.flushDrafts();
  if (!await editor.call('listDrafts') || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: editor,
      builder: (context, _) {
        final drafts = editor.maps('drafts');
        return AlertDialog(
          title: const Text('Internal drafts'),
          content: SizedBox(
            width: 420,
            height: (MediaQuery.sizeOf(context).height * .6).clamp(120.0, 420.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kept on this device. Open an unsaved copy without changing the original file. Closing this list keeps your drafts.',
                ),
                const SizedBox(height: 12),
                if (drafts.isEmpty) const Text('No closed drafts to recover.'),
                if (drafts.isNotEmpty)
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: drafts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final draft = drafts[index];
                        final timestamp = (draft['updatedAt'] as num?)?.toInt() ?? 0;
                        final date = timestamp == 0
                            ? 'Earlier recovery copy'
                            : DateTime.fromMillisecondsSinceEpoch(timestamp)
                                  .toLocal().toString().substring(0, 16);
                        final issue = draft['error'] as String?;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(draft['title'] as String? ?? 'Untitled',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(issue ?? '$date · ${draft['width']} × ${draft['height']} · ${draft['frames']} frames${draft['fallback'] == true ? '\nPrevious good copy (latest was damaged)' : ''}'),
                          onTap: editor.busy || issue != null ? null : () async {
                            if (await editor.call('recover', {'id': draft['id']}) && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          trailing: IconButton(
                            tooltip: 'Discard ${draft['title']}',
                            onPressed: editor.busy ? null : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Permanently discard draft?'),
                                  content: Text('Delete the internal copies of ${draft['title']}? Original files are not changed.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard draft')),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await editor.call('discardRecovery', {'id': draft['id']});
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
                  ),
                if (editor.error != null) Text(editor.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep editing'))],
        );
      },
    ),
  );
}
