import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'add_folder_sheet.dart';

/// Review an auto-categorized [New] save: confirm the suggestion or pick another folder.
Future<void> showConfirmItemSheet(BuildContext context, Item item) =>
    showAppSheet<void>(context, (_) => _ConfirmItemSheet(item: item));

class _ConfirmItemSheet extends StatefulWidget {
  const _ConfirmItemSheet({required this.item});
  final Item item;

  @override
  State<_ConfirmItemSheet> createState() => _ConfirmItemSheetState();
}

class _ConfirmItemSheetState extends State<_ConfirmItemSheet> {
  /// Already-confirmed links open straight into the folder picker ("Move").
  late bool _changing = !widget.item.isNew;

  Future<void> _confirm({String? moveTo}) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await state.confirmItem(widget.item, moveTo: moveTo);
    final name = state.folderById(moveTo ?? widget.item.folderId ?? kUncategorizedId)?.name ?? 'Uncategorized';
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Filed in $name')));
  }

  bool _busy = false;

  Future<void> _createYourself() async {
    final folder = await showAddFolderSheet(context);
    if (folder == null || !mounted) return;
    await _confirm(moveTo: folder.id);
  }

  Future<void> _autoCreate() async {
    setState(() => _busy = true);
    try {
      final folder = await context.read<AppState>().autoFolderFor(url: widget.item.url, title: widget.item.title);
      if (!mounted) return;
      await _confirm(moveTo: folder.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final item = widget.item;
    final suggested = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
    final color = Color(suggested.color);
    final views = item.viewCount.clamp(0, AppConfig.autoConfirmAfterViews);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        LinkThumbnail(item: item, color: color, size: 64),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: headStyle(17)),
            const SizedBox(height: 6),
            SourcePill(item.source),
          ]),
        ),
      ]),
      if (item.isNew) ...[
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: FolderPalette.soft(color), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(suggested.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(item.folderId == null ? 'No confident match' : 'Suggested: ${suggested.name}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: FolderPalette.deep(color))),
            ),
            Text('${(item.confidence * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w700, color: FolderPalette.deep(color))),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.confidence.clamp(0.05, 1.0).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: Colors.white,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        for (var i = 0; i < AppConfig.autoConfirmAfterViews; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == AppConfig.autoConfirmAfterViews - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: i < views ? AppColors.brand : AppColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
        'Shown $views of ${AppConfig.autoConfirmAfterViews} times. '
        "If you don't choose, we'll file it here the next time you open Shareby.",
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.35),
      ),
      ],
      const SizedBox(height: 16),
      if (!_changing) ...[
        FilledButton(onPressed: () => _confirm(), child: Text('Keep in ${suggested.name}')),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => setState(() => _changing = true), child: const Text('Choose a different folder')),
      ] else ...[
        FieldLabel(item.isNew ? 'File it in' : 'Move to'),
        ChoiceRow(
          selected: false,
          onTap: _busy ? () {} : _createYourself,
          title: 'Create one yourself',
          subtitle: 'Name a new folder',
          leading: const EmojiBadge(emoji: '✏️', color: Color(FolderPalette.grey)),
        ),
        ChoiceRow(
          selected: false,
          onTap: _busy ? () {} : _autoCreate,
          title: _busy ? 'Creating...' : 'Auto create suggested folder',
          subtitle: 'We pick a general name that fits, or reuse one you have',
          leading: const EmojiBadge(emoji: '✨', color: Color(FolderPalette.amber)),
        ),
        for (final f in [...state.personalFolders, Folder.uncategorized()])
          ChoiceRow(
            selected: f.id == (item.folderId ?? kUncategorizedId),
            onTap: () => _confirm(moveTo: f.id),
            title: f.name,
            leading: EmojiBadge(emoji: f.emoji, color: Color(f.color)),
          ),
      ],
    ]);
  }
}
