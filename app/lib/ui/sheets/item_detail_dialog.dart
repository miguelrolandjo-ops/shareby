import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'confirm_item_sheet.dart';
import 'edit_link_sheet.dart';
import 'item_actions_sheet.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';

/// Tapping a saved link opens this pop-out box. The picture and "Visit link" go to the link;
/// the row underneath holds the actions (pin, edit, move, sub-category, delete).
Future<void> showItemDetail(BuildContext context, Item item) =>
    showDialog<void>(context: context, builder: (_) => _ItemDetail(itemId: item.id, first: item, host: context));

class _ItemDetail extends StatelessWidget {
  const _ItemDetail({required this.itemId, required this.first, required this.host});

  final String itemId;
  final Item first;

  /// The screen underneath: follow-up sheets open from it, since this box closes first.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Live copy, so pinning or editing from here shows straight away.
    final item = state.itemById(itemId);
    if (item == null) {
      // Deleted (here or on another device): close the box.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
    final color = Color(folder.color);
    final canEdit = canDeleteItem(state, item);

    void closeThen(Future<void> Function() action) {
      Navigator.of(context).pop();
      action();
    }

    Widget action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
      final c = danger ? const Color(0xFFC0392B) : AppColors.ink;
      return TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: c),
        label: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
        style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
      );
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The picture: tap to visit the link.
          Semantics(
            button: true,
            label: tr('Open link'),
            child: InkWell(
              onTap: () => openLink(host, item.url),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(fit: StackFit.expand, children: [
                  LinkThumbnail(item: item, color: color, radius: 0),
                  Positioned(left: 12, top: 12, child: SourcePill(SourceCatalog.current.keyOf(item))),
                  if (item.isPinned) const Positioned(right: 12, top: 12, child: _PinnedChip()),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                      child: const Icon(Icons.open_in_new_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: headStyle(19)),
              if (item.author != null) ...[
                const SizedBox(height: 4),
                Text(tr('by {author}', {'author': item.author}), style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Chip(icon: Icons.folder_rounded, text: folder.name, color: color),
                if (item.tag != null) _Chip(icon: Icons.sell_outlined, text: item.tag!, color: AppColors.inkSoft),
                Text(
                    item.addedByName != null && folder.isShared
                        ? tr('Saved {when} by {name}', {'when': savedAgo(item.createdAt), 'name': item.addedByName})
                        : tr('Saved {when}', {'when': savedAgo(item.createdAt)}),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
              ]),
              if (item.isPinned && folder.isShared) ...[
                const SizedBox(height: 6),
                Text(pinnedByLabel(item, state.user?.userId),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: FilledButton.icon(
              onPressed: () => openLink(host, item.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(tr('Visit link')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Wrap(alignment: WrapAlignment.center, children: [
              if (state.canPin(item))
                action(item.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                    item.isPinned ? tr('Unpin') : tr('Pin'), () => togglePin(host, item)),
              if (canEdit) action(Icons.edit_outlined, tr('Edit'), () => closeThen(() async => showEditLinkSheet(host, item))),
              if (!folder.isShared) ...[
                action(Icons.drive_file_move_outline, item.isNew ? tr('Review') : tr('Move'),
                    () => closeThen(() async => showConfirmItemSheet(host, item))),
                action(Icons.sell_outlined, 'Sub-category', () => closeThen(() => editItemTag(host, item))),
              ],
              if (canEdit)
                action(Icons.delete_outline_rounded, folder.isShared ? tr('Remove') : tr('Delete'), () async {
                  // Ask first; the box closes only if the link was really deleted.
                  await confirmAndDeleteItem(context, item);
                }, danger: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PinnedChip extends StatelessWidget {
  const _PinnedChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.push_pin_rounded, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text(tr('Pinned'), style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
