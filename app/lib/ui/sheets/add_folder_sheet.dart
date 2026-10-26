import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../../l10n/l10n.dart';

const _emojis = ['📁', '🍳', '🏙️', '🌴', '☕', '🏀', '✨', '🏡', '🎬', '🛍️', '📚', '🎁'];

/// Create or edit a personal folder or a shared board. Returns the created folder.
Future<Folder?> showAddFolderSheet(BuildContext context, {Folder? editing, bool shared = false}) =>
    showAppSheet<Folder>(context, (_) => _AddFolderSheet(editing: editing, shared: editing?.isShared ?? shared));

class _AddFolderSheet extends StatefulWidget {
  const _AddFolderSheet({this.editing, required this.shared});
  final Folder? editing;
  final bool shared;

  @override
  State<_AddFolderSheet> createState() => _AddFolderSheetState();
}

class _AddFolderSheetState extends State<_AddFolderSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late int _color = widget.editing?.color ?? (widget.shared ? FolderPalette.lilac : FolderPalette.amber);
  late String _emoji = widget.editing?.emoji ?? (widget.shared ? '✨' : '📁');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      if (widget.editing != null) {
        await state.updateFolder(widget.editing!, name: name, color: _color, emoji: _emoji);
        navigator.pop();
      } else {
        final folder = await state.createFolder(name: name, color: _color, emoji: _emoji, shared: widget.shared);
        navigator.pop(folder);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _delete() async {
    final folder = widget.editing!;
    final state = context.read<AppState>();
    final count = state.itemsIn(folder.id).length;
    var keepLinks = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Delete "{name}"?', {'name': folder.name})),
          content: folder.isShared
              ? Text(tr('The board and its pins are removed for everyone in it.'))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(count == 0 ? tr('This folder is empty.') : trn(count, 'What should happen to the 1 link inside?', 'What should happen to the {n} links inside?')),
                  if (count > 0) ...[
                    const SizedBox(height: 8),
                    RadioGroup<bool>(
                      groupValue: keepLinks,
                      onChanged: (v) => setLocal(() => keepLinks = v ?? false),
                      child: Column(children: [
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: false,
                          title: Text(tr('Delete the links too')),
                        ),
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: true,
                          title: Text(tr('Keep them in Uncategorized')),
                        ),
                      ]),
                    ),
                  ],
                ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await state.deleteFolder(folder, keepLinks: keepLinks);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pool = widget.shared ? state.sharedFolders : state.personalFolders;
    final typed = _name.text.trim().toLowerCase();
    final duplicate = typed.isNotEmpty &&
        pool.any((f) => f.id != widget.editing?.id && f.name.toLowerCase() == typed);
    final editing = widget.editing != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetTitle(
        editing ? 'Edit ${widget.shared ? 'board' : 'folder'}' : (widget.shared ? tr('New shared board') : tr('New folder')),
        subtitle: widget.shared
            ? tr('Friends you invite can see and add pins. Shared boards have no tags or auto-sorting.')
            : tr('New saves can be sorted into it automatically.'),
      ),
      FieldLabel(tr('Name')),
      TextField(
        controller: _name,
        autofocus: !editing,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: widget.shared ? tr('e.g. Weekend Inspo') : 'e.g. Cooking',
          counterText: '',
          helperText: duplicate ? tr('You already have one with this name. This one will be saved as "{trim} (2)".', {'trim': _name.text.trim()}) : null,
          helperMaxLines: 2,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      FieldLabel(tr('Icon')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _emojis)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _emoji = e),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: e == _emoji ? FolderPalette.soft(Color(_color)) : AppColors.greySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: e == _emoji ? Color(_color) : Colors.transparent, width: 2),
              ),
              child: Text(e, style: const TextStyle(fontSize: 20)),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      FieldLabel(tr('Color')),
      Row(children: [
        for (final c in FolderPalette.all)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: c == _color ? AppColors.ink : Colors.white, width: 3),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
        child: Text(editing ? tr('Save changes') : (widget.shared ? tr('Create board') : tr('Create folder'))),
      ),
      if (editing && widget.editing!.isOwner) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _delete,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
          child: Text(widget.shared ? tr('Delete board') : tr('Delete folder')),
        ),
      ],
    ]);
  }
}
