import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import 'add_folder_sheet.dart';
import '../../l10n/l10n.dart';

/// Pick where [count] selected links should go. Returns a folder id, or [kUncategorizedId].
/// [currentFolderId] is left out of the list since the links are already there.
Future<String?> showMoveItemsSheet(BuildContext context, {required int count, required String currentFolderId}) =>
    showAppSheet<String>(context, (_) => _MoveItemsSheet(count: count, currentFolderId: currentFolderId));

class _MoveItemsSheet extends StatelessWidget {
  const _MoveItemsSheet({required this.count, required this.currentFolderId});

  final int count;
  final String currentFolderId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folders = [
      ...state.personalFolders,
      Folder.uncategorized(),
    ].where((f) => f.id != currentFolderId);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetTitle(trn(count, 'Move 1 link', 'Move {n} links')),
      ChoiceRow(
        selected: false,
        onTap: () async {
          final navigator = Navigator.of(context);
          final folder = await showAddFolderSheet(context);
          if (folder != null) navigator.pop(folder.id);
        },
        title: tr('Create one yourself'),
        subtitle: tr('Name a new folder'),
        leading: const EmojiBadge(emoji: '✏️', color: Color(FolderPalette.grey)),
      ),
      FieldLabel(tr('Move to')),
      for (final f in folders)
        ChoiceRow(
          selected: false,
          onTap: () => Navigator.of(context).pop(f.id),
          title: f.name,
          leading: EmojiBadge(emoji: f.emoji, color: Color(f.color)),
        ),
    ]);
  }
}
