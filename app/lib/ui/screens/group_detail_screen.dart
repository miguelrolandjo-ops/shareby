import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/add_folder_sheet.dart';
import '../sheets/add_link_sheet.dart';
import '../sheets/confirm_item_sheet.dart';
import '../sheets/invite_sheet.dart';
import '../sheets/move_items_sheet.dart';
import '../sheets/item_actions_sheet.dart';
import '../sheets/item_detail_dialog.dart';
import '../widgets/common.dart';
import '../widgets/item_tiles.dart';

/// One folder or shared board. Opened with [open] as a pushed route, so Back returns
/// to the list it was opened from (Home for folders, Friends for shared boards).
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.folderId});

  final String folderId;

  static Future<void> open(BuildContext context, String folderId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupDetailScreen(folderId: folderId)));

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  bool _grid = false;
  String? _filter; // a tag (personal) or a member name (shared)

  bool _retrying = false;

  Future<void> _retrySort() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _retrying = true);
    try {
      final r = await state.retryUncategorized();
      final found = r.matched == 0
          ? 'No folder fits these yet'
          : 'Found a folder for ${r.matched} ${r.matched == 1 ? 'link' : 'links'}. Confirm them on Home';
      final rest = r.matched > 0 && r.unmatched > 0 ? ' · ${r.unmatched} still unmatched' : '';
      messenger.showSnackBar(SnackBar(content: Text('$found$rest')));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Uncategorized only: re-check every link against the folders that exist now.
  Widget _retryBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Try sorting these again', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Shareby checks each link against your folders once more. '
              'Links that still match nothing stay here quietly.',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _retrying ? null : _retrySort,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _retrying
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_retrying ? 'Checking...' : 'Recategorize'),
            ),
          ]),
        ),
      );

  // Mass edit (personal folders only): pick links, drag to reorder, move or delete.
  bool _editing = false;
  final Set<String> _picked = {};
  List<String> _editOrder = [];

  void _startEditing(List<Item> all) => setState(() {
        _editing = true;
        _picked.clear();
        _editOrder = [for (final i in all) i.id];
      });

  void _stopEditing() => setState(() {
        _editing = false;
        _picked.clear();
      });

  void _reorder(int oldIndex, int newIndex) {
    setState(() => _editOrder.insert(newIndex, _editOrder.removeAt(oldIndex)));
    context.read<AppState>().setItemOrder(_editOrder);
  }

  Future<void> _moveSelected(Folder folder, List<Item> picked) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final target = await showMoveItemsSheet(context, count: picked.length, currentFolderId: folder.id);
    if (target == null || !mounted) return;
    await state.moveItems(picked, target);
    final name = state.folderById(target)?.name ?? 'Uncategorized';
    messenger.showSnackBar(SnackBar(content: Text('Moved ${picked.length} to $name')));
    _stopEditing();
  }

  /// Applies one sub-category to every selected link.
  Future<void> _tagSelected(List<Item> picked) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final existing = state.itemsIn(widget.folderId).map((i) => i.tag).whereType<String>().toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final choice = await showSubCategoryPicker(context, current: null, existing: existing);
    if (choice == null || !mounted) return;
    try {
      await state.setTags(picked, choice.name);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
      return;
    }
    final n = picked.length == 1 ? '1 link' : '${picked.length} links';
    messenger.showSnackBar(
        SnackBar(content: Text(choice.name == null ? 'Removed the sub-category from $n' : '$n added to ${choice.name}')));
    _stopEditing();
  }

  Future<void> _deleteSelected(List<Item> picked) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${picked.length == 1 ? '1 link' : '${picked.length} links'}?'),
        content: const Text('They are removed from this folder for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await state.deleteItems(picked);
    messenger.showSnackBar(SnackBar(content: Text('Deleted ${picked.length}')));
    _stopEditing();
  }

  void _onItemTap(Item item) {
    if (item.isNew) {
      showConfirmItemSheet(context, item);
    } else {
      showItemDetail(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folder = state.folderById(widget.folderId);
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg),
        body: const Center(child: Text('This folder was deleted or is no longer shared with you.')),
      );
    }

    final color = Color(folder.color);
    final all = state.itemsIn(folder.id);
    final members = folder.isShared ? state.membersOf(folder.id) : const <Member>[];
    final filters = folder.isShared
        ? members.map((m) => m.displayName).toList()
        : (all.map((i) => i.tag).whereType<String>().toSet().toList()..sort());
    // A filter can vanish (tag removed, member left); fall back to All.
    final active = (_filter != null && filters.contains(_filter)) ? _filter : null;
    final visible =
        active == null ? all : all.where((i) => folder.isShared ? i.addedByName == active : i.tag == active).toList();
    // Pinned links (most recently pinned first) sit on top; the rest follow.
    final pinned = visible.where((i) => i.isPinned).toList();
    final rest = visible.where((i) => !i.isPinned).toList();
    final pinnedCount = all.where((i) => i.isPinned).length;

    final canMassEdit = !folder.isShared && all.isNotEmpty;
    // Edit list in the user's drag order; links added meanwhile go on top.
    final byId = {for (final i in all) i.id: i};
    final editItems = [
      for (final i in all)
        if (!_editOrder.contains(i.id)) i,
      for (final id in _editOrder)
        if (byId[id] != null) byId[id]!,
    ];
    final picked = [
      for (final i in editItems)
        if (_picked.contains(i.id)) i
    ];

    return Scaffold(
      bottomNavigationBar: _editing ? _editBar(folder, editItems, picked) : null,
      floatingActionButton: folder.canAddLinks && !_editing
          ? FloatingActionButton.extended(
              onPressed: () => showAddLinkSheet(context, folderId: folder.id),
              icon: const Icon(Icons.add_link_rounded),
              label:
                  Text(folder.isShared ? 'Add pin' : 'Add link', style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        // Inside a folder a pull re-fetches only this folder's links (pages and pictures).
        onRefresh: () => context.read<AppState>().refresh(folderId: folder.id),
        // The hero is part of the scroll view, so a pull from the very top refreshes.
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
              child: _Hero(
                  folder: folder,
                  color: color,
                  count: all.length,
                  pinnedCount: pinnedCount,
                  members: members,
                  meId: state.user?.userId,
                  editing: _editing,
                  onMassEdit: canMassEdit ? (_editing ? _stopEditing : () => _startEditing(all)) : null)),
          if (!_editing)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _chip('All', active == null, () => setState(() => _filter = null)),
                        for (final f in filters) _chip(f, active == f, () => setState(() => _filter = f)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18)),
                      ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded, size: 18)),
                    ],
                    selected: {_grid},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _grid = s.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ]),
              ),
            ),
          if (folder.isUncategorized && !_editing && all.isNotEmpty) SliverToBoxAdapter(child: _retryBanner()),
          if (_editing)
            ..._editSlivers(editItems, color)
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  folder.canAddLinks
                      ? 'Nothing here yet. Share a link from Instagram, YouTube or TikTok, or tap ${folder.isShared ? 'Add pin' : 'Add link'}.'
                      : 'Nothing here yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
                ),
              ),
            )
          else ...[
            if (pinned.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Icon(Icons.push_pin_rounded, size: 17, color: color),
                    const SizedBox(width: 6),
                    Text('Pinned', style: headStyle(15)),
                    const SizedBox(width: 8),
                    Text('${pinned.length}',
                        style: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              ..._itemSlivers(pinned, folder, color, state, topPadding: 0),
            ],
            ..._groupedSlivers(rest, folder, color, state, hasPinned: pinned.isNotEmpty),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ]),
      ),
    );
  }

  /// The links that are not pinned. In a personal folder that uses sub-categories they are
  /// grouped under a header per sub-category (links without one come first); otherwise one
  /// plain list.
  List<Widget> _groupedSlivers(List<Item> todo, Folder folder, Color color, AppState state,
      {required bool hasPinned}) {
    final subs = todo.map((i) => i.tag).whereType<String>().toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final top = hasPinned ? 10.0 : 4.0;
    if (folder.isShared || subs.isEmpty) {
      return _itemSlivers(todo, folder, color, state, topPadding: top);
    }
    final loose = todo.where((i) => i.tag == null).toList();
    return [
      ..._itemSlivers(loose, folder, color, state, topPadding: top),
      for (final name in subs) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: headStyle(15))),
              const SizedBox(width: 8),
              Text('${todo.where((i) => i.tag == name).length}',
                  style: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        ..._itemSlivers(todo.where((i) => i.tag == name).toList(), folder, color, state, topPadding: 0),
      ],
    ];
  }

  /// One list or grid of links (used for the pinned part and the rest).
  List<Widget> _itemSlivers(List<Item> items, Folder folder, Color color, AppState state,
      {required double topPadding}) {
    if (items.isEmpty) return const [];
    final me = state.user?.userId;
    final padding = EdgeInsets.fromLTRB(20, topPadding, 20, 0);
    if (_grid) {
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ItemGridCard(
                item: items[i],
                color: color,
                shared: folder.isShared,
                pinLabel: pinnedByLabel(items[i], me),
                onTap: () => _onItemTap(items[i]),
                onLongPress: () => showItemActions(context, items[i]),
              ),
              childCount: items.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ];
    }
    return [
      SliverPadding(
        padding: padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => ItemTile(
              item: items[i],
              color: color,
              shared: folder.isShared,
              pinLabel: pinnedByLabel(items[i], me),
              onTap: () => _onItemTap(items[i]),
              onLongPress: () => showItemActions(context, items[i]),
              onSwipePin: state.canPin(items[i]) ? () => togglePin(context, items[i]) : null,
              onSwipeDelete: canDeleteItem(state, items[i]) ? () => confirmAndDeleteItem(context, items[i]) : null,
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  /// Mass-edit list: a checkbox and a drag handle on every link.
  List<Widget> _editSlivers(List<Item> items, Color color) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          sliver: SliverReorderableList(
            itemCount: items.length,
            onReorderItem: _reorder,
            itemBuilder: (context, i) {
              final item = items[i];
              final on = _picked.contains(item.id);
              void toggle() => setState(() => on ? _picked.remove(item.id) : _picked.add(item.id));
              return Material(
                key: ValueKey(item.id),
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: on ? FolderPalette.soft(color) : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? color : AppColors.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: toggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                      child: Row(children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.drag_handle_rounded, color: AppColors.inkFaint),
                          ),
                        ),
                        LinkThumbnail(item: item, color: color, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Checkbox(value: on, onChanged: (_) => toggle()),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ];

  Widget _editBar(Folder folder, List<Item> all, List<Item> picked) {
    final none = picked.isEmpty;
    final everything = picked.length == all.length;
    // Explicit width: the app theme gives buttons an unbounded minimum width, which is
    // what squeezed everything in a single Row before.
    const compact = Size(0, 46);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration:
            const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            TextButton(
              onPressed: () => setState(() {
                if (everything) {
                  _picked.clear();
                } else {
                  _picked.addAll(all.map((i) => i.id));
                }
              }),
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(everything ? 'Select none' : 'Select all'),
            ),
            Expanded(
              child: Text(
                none ? '' : '${picked.length} selected',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _stopEditing,
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
          if (!none) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _moveSelected(folder, picked),
                  style: OutlinedButton.styleFrom(minimumSize: compact),
                  icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  label: const Text('Move'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tagSelected(picked),
                  style: OutlinedButton.styleFrom(minimumSize: compact),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Tag', maxLines: 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _deleteSelected(picked),
                  style: FilledButton.styleFrom(minimumSize: compact, backgroundColor: const Color(0xFFC0392B)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          selectedColor: AppColors.ink,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          side: const BorderSide(color: AppColors.line),
          backgroundColor: AppColors.surface,
          shape: const StadiumBorder(),
        ),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.folder,
    required this.color,
    required this.count,
    required this.members,
    this.pinnedCount = 0,
    this.meId,
    this.editing = false,
    this.onMassEdit,
  });

  final Folder folder;
  final bool editing;
  final VoidCallback? onMassEdit;
  final int pinnedCount;
  final String? meId;
  final Color color;
  final int count;
  final List<Member> members;

  String get _subtitle {
    final done = pinnedCount > 0 ? ' · $pinnedCount pinned' : '';
    if (!folder.isShared) {
      return '${count == 1 ? '1 link' : '$count links'}$done';
    }
    final others = members.where((m) => m.userId != meId).map((m) => m.displayName).toList();
    final pins = '${count == 1 ? '1 pin' : '$count pins'}$done';
    if (others.isEmpty) return '$pins · only you so far';
    final names =
        others.length <= 2 ? others.join(' & ') : '${others.take(others.length - 1).join(', ')} & ${others.last}';
    return '$pins · shared with $names';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    Widget roundButton(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.22)),
          icon: Icon(icon, color: Colors.white),
        );

    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, FolderPalette.deep(color)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          roundButton(Icons.arrow_back_rounded, 'Back', () => Navigator.of(context).maybePop()),
          const Spacer(),
          if (folder.isShared && folder.isOwner)
            roundButton(Icons.person_add_alt_1_rounded, 'Invite', () => showInviteSheet(context, folder)),
          if (onMassEdit != null)
            roundButton(editing ? Icons.close_rounded : Icons.checklist_rounded, editing ? 'Done editing' : 'Select',
                onMassEdit!),
          if (!folder.isUncategorized && folder.isOwner && !editing) ...[
            const SizedBox(width: 8),
            roundButton(Icons.edit_rounded, 'Edit', () => showAddFolderSheet(context, editing: folder)),
          ],
        ]),
        const SizedBox(height: 22),
        Row(children: [
          Text(folder.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(child: Text(folder.name, style: headStyle(28, color: Colors.white))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (folder.isShared && members.isNotEmpty) ...[
            AvatarStack(members: members, size: 24),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(_subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5)),
          ),
        ]),
        if (folder.isShared && !folder.canAddLinks) ...[
          const SizedBox(height: 10),
          Text('You can view this board',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
        ],
      ]),
    );
  }
}
