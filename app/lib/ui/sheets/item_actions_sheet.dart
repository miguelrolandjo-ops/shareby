import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'confirm_item_sheet.dart';

/// Long-press menu for a saved link. Tag and move are personal-folder features.
Future<void> showItemActions(BuildContext context, Item item) =>
    showAppSheet<void>(context, (_) => _ItemActions(item: item, host: context));

class _ItemActions extends StatelessWidget {
  const _ItemActions({required this.item, required this.host});
  final Item item;

  /// The screen that opened this sheet. Follow-up dialogs open from it, because
  /// this sheet's own context goes away as soon as it closes.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
    final me = state.user?.userId;
    final canDelete = !folder.isShared || folder.isOwner || item.addedBy == me;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        LinkThumbnail(item: item, color: Color(folder.color), size: 48),
        const SizedBox(width: 12),
        Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: headStyle(16))),
      ]),
      const SizedBox(height: 12),
      _action(context, Icons.open_in_new_rounded, 'Open link', () => openLink(host, item.url)),
      if (state.canMarkDone(item))
        _action(
          context,
          item.isDone ? Icons.radio_button_unchecked_rounded : Icons.check_circle_outline_rounded,
          item.isDone ? 'Mark as not done' : 'Mark as done',
          () async {
            if (host.mounted) await toggleDone(host, item);
          },
        ),
      if (!folder.isShared) ...[
        if (item.isNew)
          _action(context, Icons.fact_check_rounded, 'Review suggestion', () => showConfirmItemSheet(host, item)),
        _action(context, Icons.sell_outlined, item.tag == null ? 'Add a tag' : 'Edit tag "${item.tag}"',
            () => _editTag(state)),
        _action(context, Icons.drive_file_move_outline, 'Move to another folder', () => showConfirmItemSheet(host, item)),
      ],
      if (canDelete)
        _action(context, Icons.delete_outline_rounded, folder.isShared ? 'Remove pin' : 'Delete link', () async {
          await state.deleteItem(item);
        }, danger: true),
    ]);
  }

  Widget _action(BuildContext context, IconData icon, String label, Future<void> Function() onTap, {bool danger = false}) {
    final color = danger ? const Color(0xFFC0392B) : AppColors.ink;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  Future<void> _editTag(AppState state) async {
    if (!host.mounted) return;
    final controller = TextEditingController(text: item.tag ?? '');
    final tag = await showDialog<String>(
      context: host,
      builder: (ctx) => AlertDialog(
        title: const Text('Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'e.g. Must try'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (tag == null) return;
    await state.setTag(item, tag);
  }
}
