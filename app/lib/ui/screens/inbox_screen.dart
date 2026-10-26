import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/confirm_item_sheet.dart';
import '../sheets/item_actions_sheet.dart';
import '../widgets/item_tiles.dart';

/// Every auto-categorized save still waiting for a yes/no.
/// Swipe right keeps the suggestion (with Undo); swipe left deletes after asking.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  Future<void> _keep(BuildContext context, AppState state, Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = state.folderById(item.folderId ?? kUncategorizedId)?.name ?? tr('Uncategorized');
    try {
      await state.confirmItem(item);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Filed in {folder}', {'folder': name})),
        action: SnackBarAction(label: tr('Undo'), onPressed: () => state.restoreItem(item)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.newItems;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(tr('Needs a quick look'), style: headStyle(26)),
            const SizedBox(height: 6),
            Text(
              tr('We guessed where these belong. Swipe right to keep the suggestion, left to delete, or tap '
                  "to open the link or pick another folder. Ones you skip are filed automatically after they've "
                  'been shown {n} times.', {'n': AppConfig.autoConfirmAfterViews}),
              style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(children: [
                  const Icon(Icons.task_alt_rounded, size: 44, color: AppColors.brand),
                  const SizedBox(height: 10),
                  Text(tr("You're all caught up"), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(tr('Links you save with "Sort it for me" show up here.'),
                      textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
                ]),
              )
            else
              for (final item in items)
                () {
                  final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
                  return ItemTile(
                    key: ValueKey(item.id),
                    item: item,
                    color: Color(folder.color),
                    folderLabel: tr('Suggested: {folder}', {'folder': folder.name}),
                    onTap: () => showConfirmItemSheet(context, item),
                    onLongPress: () => showItemActions(context, item),
                    onSwipeKeep: () => _keep(context, state, item),
                    keepLabel: tr('Keep in {folder}', {'folder': folder.name}),
                    onSwipeDelete: () async {
                      if (await confirmAndDeleteItem(context, item) && context.mounted) {
                        toast(context, tr('Link deleted'));
                      }
                    },
                  );
                }(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
