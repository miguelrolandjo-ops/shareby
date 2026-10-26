import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/add_folder_sheet.dart';
import '../sheets/confirm_item_sheet.dart';
import '../widgets/common.dart';
import 'group_detail_screen.dart';
import 'refactor_screen.dart';
import 'profile_screen.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenSearch, required this.onOpenInbox});

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folders = state.personalFolders;
    final newItems = state.newItems;
    final tiles = <Folder>[...folders, if (state.hasUncategorized) Folder.uncategorized()];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pasteFromClipboard(context),
        icon: const Icon(Icons.content_paste_rounded),
        label: Text(tr('Paste link'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: state.refresh,
          child: ListView(
            // Always pullable, even when everything fits on screen.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _Header(state: state),
              const SizedBox(height: 16),
              _SearchEntry(onTap: onOpenSearch),
              if (newItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionTitle(tr('Needs a quick look'),
                    trailing: TextButton(onPressed: onOpenInbox, child: Text(tr('See all ({newItems})', {'newItems': newItems.length})))),
                SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: newItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _NewItemCard(item: newItems[i]),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SectionTitle(tr('Your collections')),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: tiles.length + (state.personalItems.isEmpty ? 1 : 2),
                itemBuilder: (context, i) {
                  if (i == tiles.length) return const _NewFolderCard();
                  if (i == tiles.length + 1) return const _RefactorCard();
                  final f = tiles[i];
                  final inside = state.itemsIn(f.id);
                  final card = FolderCard(
                    folder: f,
                    count: inside.length,
                    newCount: inside.where((it) => it.isNew).length,
                    pinnedCount: inside.where((it) => it.isPinned).length,
                    onTap: () => GroupDetailScreen.open(context, f.id),
                  );
                  // Uncategorized is not a real folder: it can't be moved or edited.
                  if (f.isUncategorized) return card;
                  return MovableFolderTile(
                    key: ValueKey(f.id),
                    folder: f,
                    onDrop: (dragged, target) => _moveFolder(state, dragged, target),
                    onEdit: (folder) => showAddFolderSheet(context, editing: folder),
                    child: card,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drops [dragged] into [target]'s place and saves the new order of the folders.
void _moveFolder(AppState state, Folder dragged, Folder target) {
  final ids = [for (final f in state.personalFolders) f.id];
  final from = ids.indexOf(dragged.id);
  final to = ids.indexOf(target.id);
  if (from < 0 || to < 0 || from == to) return;
  ids.removeAt(from);
  ids.insert(to, dragged.id);
  state.setFolderOrder(ids);
}

/// A folder on Home that responds to touch-and-hold:
///  * hold, then let go without moving: opens the folder's Edit sheet;
///  * hold, then drag more than [slop] pixels: picks the folder up so it can be dropped
///    on another folder to take its place (no Edit sheet when it is dropped).
/// The page scrolls by itself when a held folder is dragged near the top or bottom.
class MovableFolderTile extends StatefulWidget {
  const MovableFolderTile({
    super.key,
    required this.folder,
    required this.child,
    required this.onDrop,
    required this.onEdit,
  });

  final Folder folder;
  final Widget child;
  final void Function(Folder dragged, Folder target) onDrop;

  /// Called when the folder is held and let go without being dragged.
  final void Function(Folder folder) onEdit;

  @override
  State<MovableFolderTile> createState() => MovableFolderTileState();
}

class MovableFolderTileState extends State<MovableFolderTile> {
  /// Android's touch slop: a finger can wobble this far and still count as holding still.
  static const slop = 8.0;

  Offset? _down;
  Offset _last = Offset.zero;
  bool _moved = false;
  Timer? _scroller;

  @override
  void dispose() {
    _scroller?.cancel();
    super.dispose();
  }

  /// The page's own scroll view: the first scrollable above the folder grid (which doesn't scroll).
  ScrollPosition? _pageScroll() {
    final grid = context.findAncestorStateOfType<ScrollableState>();
    final page = grid?.context.findAncestorStateOfType<ScrollableState>();
    return (page ?? grid)?.position;
  }

  void _startAutoScroll() {
    _scroller?.cancel();
    _scroller = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final position = _pageScroll();
      if (position == null || !mounted) return;
      final view = MediaQuery.of(context);
      final top = view.padding.top + 100;
      final bottom = view.size.height - 150;
      var step = 0.0;
      if (_last.dy < top) {
        step = -10;
      } else if (_last.dy > bottom) {
        step = 10;
      }
      if (step != 0) {
        position.jumpTo((position.pixels + step).clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    });
  }

  void _stopAutoScroll() {
    _scroller?.cancel();
    _scroller = null;
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    return DragTarget<Folder>(
      onWillAcceptWithDetails: (d) => d.data.id != folder.id,
      onAcceptWithDetails: (d) => widget.onDrop(d.data, folder),
      builder: (context, candidates, _) => LayoutBuilder(
        builder: (context, box) => Listener(
          onPointerDown: (e) => _down = e.position,
          child: LongPressDraggable<Folder>(
            data: folder,
            hapticFeedbackOnStart: true,
            onDragStarted: () {
              _moved = false;
              _last = _down ?? Offset.zero;
              _startAutoScroll();
            },
            onDragUpdate: (d) {
              _last = d.globalPosition;
              if (!_moved && _down != null && (d.globalPosition - _down!).distance > slop) _moved = true;
            },
            onDragEnd: (_) {
              _stopAutoScroll();
              if (!_moved && mounted) widget.onEdit(folder);
            },
            onDraggableCanceled: (_, __) => _stopAutoScroll(),
            feedback: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Transform.scale(
                scale: 1.05,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Material(color: Colors.transparent, child: widget.child),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: candidates.isEmpty ? Colors.transparent : AppColors.brand, width: 2),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final name = state.user?.displayName;
    final waiting = state.newItems.length;
    void openProfile() => ProfileScreen.open(context);

    return Row(children: [
      InkWell(
        customBorder: const CircleBorder(),
        onTap: openProfile,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.brand, Color(0xFF2FA88F)]),
          ),
          child: name == null
              ? const Icon(Icons.person_rounded, color: Colors.white)
              : Text(name.substring(0, 1).toUpperCase(), style: headStyle(20, color: Colors.white)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name == null ? tr('Hi there') : 'Hi, ${name.split(' ').first}', style: headStyle(22)),
          const SizedBox(height: 2),
          Text(
            waiting == 0
                ? tr('All caught up')
                : (waiting == 1 ? tr('1 save needs a quick look') : tr('{waiting} saves need a quick look', {'waiting': waiting})),
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
        ]),
      ),
      IconButton(
        tooltip: tr('Settings'),
        onPressed: openProfile,
        icon: const Icon(Icons.settings_outlined, color: AppColors.inkSoft),
      ),
    ]);
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Icon(Icons.search_rounded, color: AppColors.inkFaint),
            SizedBox(width: 10),
            Text(tr('Search your saves'), style: TextStyle(color: AppColors.inkFaint)),
          ]),
        ),
      ),
    );
  }
}

class _NewItemCard extends StatelessWidget {
  const _NewItemCard({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
    final color = Color(folder.color);

    return SizedBox(
      width: 172,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showConfirmItemSheet(context, item),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 92,
              child: Stack(fit: StackFit.expand, children: [
                LinkThumbnail(item: item, color: color, radius: 0),
                const Positioned(left: 8, top: 8, child: NewPill()),
                Positioned(right: 8, top: 8, child: SourcePill(SourceCatalog.current.keyOf(item))),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.3)),
                  const SizedBox(height: 4),
                  Text('${folder.emoji} ${folder.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: FolderPalette.deep(color), fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: EdgeInsets.zero),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await state.confirmItem(item);
                          messenger.showSnackBar(SnackBar(content: Text(tr('Filed in {name}', {'name': folder.name}))));
                        },
                        child: Text(tr('Confirm'), style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: EdgeInsets.zero),
                        onPressed: () => showConfirmItemSheet(context, item),
                        child: Text(tr('Change'), style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NewFolderCard extends StatelessWidget {
  const _NewFolderCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showAddFolderSheet(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: 28, color: AppColors.brand),
            SizedBox(height: 6),
            Text(tr('New folder'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
          ]),
        ),
      ),
    );
  }
}

class _RefactorCard extends StatelessWidget {
  const _RefactorCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => RefactorScreen.open(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.auto_awesome_rounded, size: 26, color: AppColors.brand),
            SizedBox(height: 6),
            Text(tr('Refactor'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
            Text(tr('Regroup all links'), style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ]),
        ),
      ),
    );
  }
}
