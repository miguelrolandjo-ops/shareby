import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'confirm_item_sheet.dart';
import 'edit_link_sheet.dart';
import '../../l10n/l10n.dart';

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
    final canDelete = canDeleteItem(state, item);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        LinkThumbnail(item: item, color: Color(folder.color), size: 48),
        const SizedBox(width: 12),
        Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: headStyle(16))),
      ]),
      const SizedBox(height: 12),
      _action(context, Icons.open_in_new_rounded, tr('Open link'), () => openLink(host, item.url)),
      if (state.canPin(item))
        _action(
          context,
          item.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          item.isPinned ? tr('Unpin') : tr('Pin to top'),
          () async {
            if (host.mounted) await togglePin(host, item);
          },
        ),
      if (canDelete) _action(context, Icons.edit_outlined, tr('Edit link'), () async => showEditLinkSheet(host, item)),
      if (!folder.isShared) ...[
        if (item.isNew)
          _action(context, Icons.fact_check_rounded, tr('Review suggestion'), () => showConfirmItemSheet(host, item)),
        _action(context, Icons.sell_outlined, item.tag == null ? tr('Set sub-category') : 'Sub-category: ${item.tag}',
            () => editItemTag(host, item)),
        _action(
            context, Icons.drive_file_move_outline, tr('Move to another folder'), () => showConfirmItemSheet(host, item)),
      ],
      if (canDelete)
        _action(context, Icons.delete_outline_rounded, folder.isShared ? tr('Remove pin') : tr('Delete link'), () async {
          if (host.mounted) await confirmAndDeleteItem(host, item);
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
}

/// Picks a sub-category for one link and saves it.
Future<void> editItemTag(BuildContext host, Item item) async {
  if (!host.mounted) return;
  final state = host.read<AppState>();
  final existing = _subCategoriesIn(state, item.folderId ?? kUncategorizedId);
  final picked = await showSubCategoryPicker(host, current: item.tag, existing: existing);
  if (picked == null) return;
  try {
    await state.setTag(item, picked.name);
  } catch (e) {
    if (host.mounted) toast(host, friendlyError(e));
  }
}

List<String> _subCategoriesIn(AppState state, String folderId) =>
    state.itemsIn(folderId).map((i) => i.tag).whereType<String>().toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

/// Opens the sub-category sheet. null = dismissed; a [SubChoice] with a null name = remove it.
Future<SubChoice?> showSubCategoryPicker(BuildContext host,
        {required String? current, required List<String> existing}) =>
    showAppSheet<SubChoice>(host, (_) => _SubCategorySheet(current: current, existing: existing));

/// What the user chose in the sub-category sheet; [name] null = remove it.
class SubChoice {
  const SubChoice(this.name);
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
    Navigator.of(context).pop(SubChoice(same.isNotEmpty ? same.first : name));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetTitle(tr('Sub-category'), subtitle: tr('Group links inside this folder.')),
      TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 40,
        decoration: InputDecoration(
          hintText: tr('New sub-category, e.g. Dance practice'),
          counterText: '',
          suffixIcon: IconButton(tooltip: tr('Add'), icon: const Icon(Icons.check_rounded), onPressed: _submitNew),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submitNew(),
      ),
      if (widget.existing.isNotEmpty) ...[
        FieldLabel(tr('In this folder')),
        for (final name in widget.existing)
          ChoiceRow(
            selected: name == widget.current,
            onTap: () => Navigator.of(context).pop(SubChoice(name)),
            title: name,
            leading: const EmojiBadge(emoji: '📂', color: Color(FolderPalette.grey)),
          ),
      ],
      if (widget.current != null)
        ChoiceRow(
          selected: false,
          onTap: () => Navigator.of(context).pop(const SubChoice(null)),
          title: tr('No sub-category'),
          leading: const EmojiBadge(emoji: '✖️', color: Color(FolderPalette.grey)),
        ),
    ]);
  }
}
