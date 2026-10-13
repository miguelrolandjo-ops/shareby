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
        _action(context, Icons.sell_outlined, item.tag == null ? 'Set sub-category' : 'Sub-category: ${item.tag}',
            () => _editTag(state)),
        _action(
            context, Icons.drive_file_move_outline, 'Move to another folder', () => showConfirmItemSheet(host, item)),
      ],
      if (canDelete)
        _action(context, Icons.delete_outline_rounded, folder.isShared ? 'Remove pin' : 'Delete link', () async {
          await state.deleteItem(item);
        }, danger: true),
    ]);
  }

  Widget _action(BuildContext context, IconData icon, String label, Future<void> Function() onTap,
      {bool danger = false}) {
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
    final siblings = state.itemsIn(item.folderId ?? kUncategorizedId);
    final existing = siblings.map((i) => i.tag).whereType<String>().toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final picked =
        await showAppSheet<_SubChoice>(host, (_) => _SubCategorySheet(current: item.tag, existing: existing));
    if (picked == null) return;
    await state.setTag(item, picked.name);
  }
}

/// What the user chose in the sub-category sheet; [name] null = remove it.
class _SubChoice {
  const _SubChoice(this.name);
  final String? name;
}

/// Sub-categories live inside one folder (e.g. "K-Pop" > "Dance practice"). Pick one the
/// folder already has, make a new one, or clear it.
class _SubCategorySheet extends StatefulWidget {
  const _SubCategorySheet({required this.current, required this.existing});

  final String? current;
  final List<String> existing;

  @override
  State<_SubCategorySheet> createState() => _SubCategorySheetState();
}

class _SubCategorySheetState extends State<_SubCategorySheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitNew() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    // Reuse the folder's spelling if it already has this sub-category.
    final same = widget.existing.where((e) => e.toLowerCase() == name.toLowerCase());
    Navigator.of(context).pop(_SubChoice(same.isNotEmpty ? same.first : name));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const SheetTitle('Sub-category', subtitle: 'Group links inside this folder.'),
      TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 40,
        decoration: InputDecoration(
          hintText: 'New sub-category, e.g. Dance practice',
          counterText: '',
          suffixIcon: IconButton(tooltip: 'Add', icon: const Icon(Icons.check_rounded), onPressed: _submitNew),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submitNew(),
      ),
      if (widget.existing.isNotEmpty) ...[
        const FieldLabel('In this folder'),
        for (final name in widget.existing)
          ChoiceRow(
            selected: name == widget.current,
            onTap: () => Navigator.of(context).pop(_SubChoice(name)),
            title: name,
            leading: const EmojiBadge(emoji: '📂', color: Color(FolderPalette.grey)),
          ),
      ],
      if (widget.current != null)
        ChoiceRow(
          selected: false,
          onTap: () => Navigator.of(context).pop(const _SubChoice(null)),
          title: 'No sub-category',
          leading: const EmojiBadge(emoji: '✖️', color: Color(FolderPalette.grey)),
        ),
    ]);
  }
}
