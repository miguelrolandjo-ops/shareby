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
import '../sheets/item_actions_sheet.dart';
import '../widgets/common.dart';
import '../widgets/item_tiles.dart';

/// One folder or shared board. Opened with [open] as a pushed route, so Back returns
/// to the list it was opened from (Home for folders, Friends for shared boards).
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.folderId});

  final String folderId;

  static Future<void> open(BuildContext context, String folderId) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => GroupDetailScreen(folderId: folderId)));

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  bool _grid = false;
  bool _doneCollapsed = false;
  String? _filter; // a tag (personal) or a member name (shared)

  void _onItemTap(Item item) {
    if (item.isNew) {
      showConfirmItemSheet(context, item);
    } else {
      openLink(context, item.url);
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
    final visible = active == null
        ? all
        : all.where((i) => folder.isShared ? i.addedByName == active : i.tag == active).toList();
    // To-do first; done links sink into their own section, most recently done first.
    final todo = visible.where((i) => !i.isDone).toList();
    final done = visible.where((i) => i.isDone).toList()
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    final doneCount = all.where((i) => i.isDone).length;

    return Scaffold(
      floatingActionButton: folder.canAddLinks
          ? FloatingActionButton.extended(
              onPressed: () => showAddLinkSheet(context, folderId: folder.id),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(folder.isShared ? 'Add pin' : 'Add link', style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: _Hero(
                folder: folder,
                color: color,
                count: all.length,
                doneCount: doneCount,
                members: members,
                meId: state.user?.userId)),
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
        if (visible.isEmpty)
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
          ..._itemSlivers(todo, folder, color, state, topPadding: 4),
          if (done.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Text('Done', style: headStyle(16, color: AppColors.inkSoft)),
                  const SizedBox(width: 8),
                  Text('${done.length}', style: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _doneCollapsed = !_doneCollapsed),
                    child: Text(_doneCollapsed ? 'Show' : 'Hide'),
                  ),
                ]),
              ),
            ),
            if (!_doneCollapsed) ..._itemSlivers(done, folder, color, state, topPadding: 0),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ]),
    );
  }

  /// One list or grid of links (used for the to-do part and the Done part).
  List<Widget> _itemSlivers(List<Item> items, Folder folder, Color color, AppState state, {required double topPadding}) {
    if (items.isEmpty) return const [];
    final me = state.user?.userId;
    VoidCallback? toggle(Item i) => state.canMarkDone(i) ? () => toggleDone(context, i) : null;
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
                doneLabel: doneByLabel(items[i], me),
                onTap: () => _onItemTap(items[i]),
                onLongPress: () => showItemActions(context, items[i]),
                onToggleDone: toggle(items[i]),
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
              doneLabel: doneByLabel(items[i], me),
              onTap: () => _onItemTap(items[i]),
              onLongPress: () => showItemActions(context, items[i]),
              onToggleDone: toggle(items[i]),
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
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
    this.doneCount = 0,
    this.meId,
  });

  final Folder folder;
  final int doneCount;
  final String? meId;
  final Color color;
  final int count;
  final List<Member> members;

  String get _subtitle {
    final done = doneCount > 0 ? ' · $doneCount done' : '';
    if (!folder.isShared) {
      return '${count == 1 ? '1 link' : '$count links'}$done';
    }
    final others = members.where((m) => m.userId != meId).map((m) => m.displayName).toList();
    final pins = '${count == 1 ? '1 pin' : '$count pins'}$done';
    if (others.isEmpty) return '$pins · only you so far';
    final names = others.length <= 2
        ? others.join(' & ')
        : '${others.take(others.length - 1).join(', ')} & ${others.last}';
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
          if (!folder.isUncategorized && folder.isOwner) ...[
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
          Text('You can view this board', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
        ],
      ]),
    );
  }
}
