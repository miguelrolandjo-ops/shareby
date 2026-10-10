import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: Text(folder.isShared
            ? 'The board and its pins are removed for everyone in it.'
            : 'Its links move to Uncategorized. Nothing you saved is lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await context.read<AppState>().deleteFolder(folder);
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
        editing ? 'Edit ${widget.shared ? 'board' : 'folder'}' : (widget.shared ? 'New shared board' : 'New folder'),
        subtitle: widget.shared
            ? 'Friends you invite can see and add pins. Shared boards have no tags or auto-sorting.'
            : 'New saves can be sorted into it automatically.',
      ),
      const FieldLabel('Name'),
      TextField(
        controller: _name,
        autofocus: !editing,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: widget.shared ? 'e.g. Weekend Inspo' : 'e.g. Cooking',
          counterText: '',
          helperText: duplicate ? 'You already have one with this name. This one will be saved as "${_name.text.trim()} (2)".' : null,
          helperMaxLines: 2,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      const FieldLabel('Icon'),
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
      const FieldLabel('Color'),
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
        child: Text(editing ? 'Save changes' : (widget.shared ? 'Create board' : 'Create folder')),
      ),
      if (editing && widget.editing!.isOwner) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _delete,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
          child: Text('Delete ${widget.shared ? 'board' : 'folder'}'),
        ),
      ],
    ]);
  }
}
