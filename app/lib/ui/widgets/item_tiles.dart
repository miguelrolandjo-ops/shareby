import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

/// A saved link as a list row. Shared boards show who added it; personal folders show tags.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.onToggleDone,
    this.doneLabel,
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

  /// Shows the done tick when set (null for [New] items and for viewers).
  final VoidCallback? onToggleDone;

  /// "Done by Diana" on shared boards.
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final meta = folderLabel ??
        (shared
            ? (item.isDone ? (doneLabel ?? 'Done') : 'added by ${item.addedByName ?? 'someone'}')
            : item.tag);
    final done = item.isDone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
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
              Opacity(opacity: done ? 0.55 : 1, child: LinkThumbnail(item: item, color: color, size: 58)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                        color: done ? AppColors.inkFaint : AppColors.ink,
                      )),
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
              if (item.isNew)
                const Padding(padding: EdgeInsets.only(right: 4), child: NewPill())
              else if (onToggleDone != null)
                DoneToggle(done: done, onTap: onToggleDone!)
              else if (shared)
                InitialAvatar(name: item.addedByName ?? '?', seed: item.addedBy, size: 30)
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ]),
          ),
        ),
      ),
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
    this.onToggleDone,
    this.doneLabel,
    this.shared = false,
  });

  final Item item;
  final Color color;
  final bool shared;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleDone;
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final done = item.isDone;
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
              Opacity(opacity: done ? 0.55 : 1, child: LinkThumbnail(item: item, color: color, radius: 0)),
              Positioned(left: 8, top: 8, child: SourcePill(item.source)),
              if (item.isNew) const Positioned(right: 8, top: 8, child: NewPill()),
              if (!item.isNew && onToggleDone != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: DoneToggle(done: done, onTap: onToggleDone!, size: 26, filledBackground: true),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.3,
                    color: done ? AppColors.inkFaint : AppColors.ink,
                  )),
              if (shared) ...[
                const SizedBox(height: 4),
                Text(done ? (doneLabel ?? 'Done') : 'by ${item.addedByName ?? 'someone'}',
                    maxLines: 1, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ] else if (item.tag != null) ...[
                const SizedBox(height: 4),
                Text(item.tag!, maxLines: 1, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
