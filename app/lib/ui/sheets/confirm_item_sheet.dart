import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'add_folder_sheet.dart';
import '../../data/sources.dart';

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
    final name = state.folderById(moveTo ?? widget.item.folderId ?? kUncategorizedId)?.name ?? tr('Uncategorized');
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(tr('Filed in {name}', {'name': name}))));
  }

  bool _busy = false;

  /// Asks first (OK / Cancel), then deletes and closes the sheet.
  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await confirmAndDeleteItem(context, widget.item)) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('Link deleted'))));
    }
  }

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
      // Tapping the link opens it first, for when you don't remember what it was. Opening
      // doesn't file it; the choice below still decides.
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openLink(context, item.url),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            LinkThumbnail(item: item, color: color, size: 64),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: headStyle(17)),
              const SizedBox(height: 6),
              Row(children: [
                SourcePill(SourceCatalog.current.keyOf(item)),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.brand),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(tr('Open link'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
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
              child: Text(item.folderId == null ? tr('No confident match') : 'Suggested: ${suggested.name}',
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
        tr("Shown {views} of {autoConfirmAfterViews} times. If you don't choose, we'll file it here the next time you open Shareby.", {'views': views, 'autoConfirmAfterViews': AppConfig.autoConfirmAfterViews}),
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.35),
      ),
      ],
      const SizedBox(height: 16),
      if (!_changing) ...[
        FilledButton(onPressed: () => _confirm(), child: Text(tr('Keep in {folder}', {'folder': suggested.name}))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _changing = true),
              child: Text(tr('Choose a different folder')),
            ),
          ),
          const SizedBox(width: 10),
          // Square, as tall as the buttons: drop a save you don't want after all.
          SizedBox(
            width: 52,
            height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(52, 52),
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFFC0392B),
                side: const BorderSide(color: Color(0x55C0392B)),
              ),
              onPressed: _delete,
              child: Tooltip(message: tr('Delete'), child: const Icon(Icons.delete_outline_rounded)),
            ),
          ),
        ]),
      ] else ...[
        FieldLabel(item.isNew ? tr('File it in') : tr('Move to')),
        ChoiceRow(
          selected: false,
          onTap: _busy ? () {} : _createYourself,
          title: tr('Create one yourself'),
          subtitle: tr('Name a new folder'),
          leading: const EmojiBadge(emoji: '✏️', color: Color(FolderPalette.grey)),
        ),
        ChoiceRow(
          selected: false,
          onTap: _busy ? () {} : _autoCreate,
          title: _busy ? 'Creating...' : tr('Auto create suggested folder'),
          subtitle: tr('We pick a general name that fits, or reuse one you have'),
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
