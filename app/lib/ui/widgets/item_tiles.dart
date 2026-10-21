import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

/// A saved link as a list row. Shared boards show who added it; personal folders show tags.
///
/// Swipe right pins it ([onSwipePin], in the folder's accent colour), swipe left deletes it
/// ([onSwipeDelete], which should ask for confirmation). Either is off when null.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.onSwipePin,
    this.onSwipeDelete,
    this.pinLabel,
    this.shared = false,
    this.folderLabel,
  });

  final Item item;
  final Color color;
  final bool shared;

  /// Shown instead of the tag, e.g. in search results.
  final String? folderLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Pin or unpin (null for [New] items and for viewers, which turns the swipe off).
  final VoidCallback? onSwipePin;

  /// Asks, then deletes. Called when the user swipes left.
  final Future<void> Function()? onSwipeDelete;

  /// "Pinned by Diana" on shared boards.
  final String? pinLabel;

  @override
  Widget build(BuildContext context) {
    final meta = folderLabel ??
        (shared ? (item.isPinned ? (pinLabel ?? 'Pinned') : 'added by ${item.addedByName ?? 'someone'}') : (item.author ?? item.tag));
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            LinkThumbnail(item: item, color: color, size: 58),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3, color: AppColors.ink)),
                const SizedBox(height: 6),
                Row(children: [
                  SourcePill(item.source),
                  if (meta != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                    ),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 4),
            if (item.isPinned) Padding(padding: const EdgeInsets.only(right: 4), child: PinBadge(color: color)),
            if (item.isNew)
              const Padding(padding: EdgeInsets.only(right: 4), child: NewPill())
            else if (shared)
              InitialAvatar(name: item.addedByName ?? '?', seed: item.addedBy, size: 30)
            else if (!item.isPinned)
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ]),
        ),
      ),
    );

    final direction = onSwipePin != null && onSwipeDelete != null
        ? DismissDirection.horizontal
        : onSwipePin != null
            ? DismissDirection.startToEnd
            : onSwipeDelete != null
                ? DismissDirection.endToStart
                : DismissDirection.none;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: direction == DismissDirection.none
          ? card
          : Dismissible(
              key: ValueKey('swipe-${item.id}'),
              direction: direction,
              dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.4},
              background: _SwipeBackground(
                color: color,
                icon: item.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                label: item.isPinned ? 'Unpin' : 'Pin',
                alignment: Alignment.centerLeft,
              ),
              secondaryBackground: const _SwipeBackground(
                color: Color(0xFFC0392B),
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                alignment: Alignment.centerRight,
              ),
              // The action is done here, and the row always springs back: the list itself
              // re-sorts (pinned to the top) or drops the link once the change lands.
              confirmDismiss: (dir) async {
                if (dir == DismissDirection.startToEnd) {
                  onSwipePin?.call();
                } else {
                  await onSwipeDelete?.call();
                }
                return false;
              },
              child: card,
            ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.color, required this.icon, required this.label, required this.alignment});

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    final children = [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: left ? children : children.reversed.toList()),
    );
  }
}

/// A saved link as a grid card.
class ItemGridCard extends StatelessWidget {
  const ItemGridCard({
    super.key,
    required this.item,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.pinLabel,
    this.shared = false,
  });

  final Item item;
  final Color color;
  final bool shared;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? pinLabel;

  @override
  Widget build(BuildContext context) {
    final pinned = item.isPinned;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              LinkThumbnail(item: item, color: color, radius: 0),
              Positioned(left: 8, top: 8, child: SourcePill(item.source)),
              if (item.isNew) const Positioned(right: 8, top: 8, child: NewPill()),
              if (pinned && !item.isNew)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: const Icon(Icons.push_pin_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.3, color: AppColors.ink)),
              if (shared) ...[
                const SizedBox(height: 4),
                Text(pinned ? (pinLabel ?? 'Pinned') : 'by ${item.addedByName ?? 'someone'}',
                    maxLines: 1, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ] else if (item.author != null || item.tag != null) ...[
                const SizedBox(height: 4),
                Text(item.author ?? item.tag!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
