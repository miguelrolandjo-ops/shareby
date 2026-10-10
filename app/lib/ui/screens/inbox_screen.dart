import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../sheets/confirm_item_sheet.dart';
import '../sheets/item_actions_sheet.dart';
import '../widgets/common.dart';
import '../widgets/item_tiles.dart';

/// Every auto-categorized save still waiting for a yes/no.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

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
            Text('Needs a quick look', style: headStyle(26)),
            const SizedBox(height: 6),
            const Text(
              'We guessed where these belong. Tap one to keep the suggestion or pick another folder. '
              "Ones you skip are filed automatically after they've been shown "
              '${AppConfig.autoConfirmAfterViews} times.',
              style: TextStyle(color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Column(children: [
                  Icon(Icons.task_alt_rounded, size: 44, color: AppColors.brand),
                  SizedBox(height: 10),
                  Text("You're all caught up", style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('Links you save with "Sort it for me" show up here.',
                      style: TextStyle(color: AppColors.inkSoft)),
                ]),
              )
            else
              for (final item in items)
                ItemTile(
                  item: item,
                  color: Color((state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized()).color),
                  folderLabel: 'Suggested: ${state.folderById(item.folderId ?? kUncategorizedId)?.name ?? 'Uncategorized'}',
                  onTap: () => showConfirmItemSheet(context, item),
                  onLongPress: () => showItemActions(context, item),
                ),
            const SizedBox(height: 12),
            const InfoNote(text: 'Auto-sorting only uses your personal folders. Shared boards are never auto-filled.'),
          ],
        ),
      ),
    );
  }
}
