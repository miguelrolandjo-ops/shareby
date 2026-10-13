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
        label: const Text('Paste link', style: TextStyle(fontWeight: FontWeight.w700)),
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
                SectionTitle('Needs a quick look',
                    trailing: TextButton(onPressed: onOpenInbox, child: Text('See all (${newItems.length})'))),
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
              const SectionTitle('Your collections'),
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
                  return FolderCard(
                    folder: f,
                    count: inside.length,
                    newCount: inside.where((it) => it.isNew).length,
                    doneCount: inside.where((it) => it.isDone).length,
                    onTap: () => GroupDetailScreen.open(context, f.id),
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
              : Text(name.substring(0, 1).toUpperCase(),
                  style: headStyle(20, color: Colors.white)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name == null ? 'Hi there' : 'Hi, ${name.split(' ').first}', style: headStyle(22)),
          const SizedBox(height: 2),
          Text(
            waiting == 0 ? 'All caught up' : (waiting == 1 ? '1 save needs a quick look' : '$waiting saves need a quick look'),
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
        ]),
      ),
      IconButton(
        tooltip: 'Settings',
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
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Icon(Icons.search_rounded, color: AppColors.inkFaint),
            SizedBox(width: 10),
            Text('Search your saves', style: TextStyle(color: AppColors.inkFaint)),
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
                Positioned(right: 8, top: 8, child: SourcePill(item.source)),
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
                          messenger.showSnackBar(SnackBar(content: Text('Filed in ${folder.name}')));
                        },
                        child: const Text('Confirm', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: EdgeInsets.zero),
                        onPressed: () => showConfirmItemSheet(context, item),
                        child: const Text('Change', style: TextStyle(fontSize: 12.5)),
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
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_rounded, size: 28, color: AppColors.brand),
            SizedBox(height: 6),
            Text('New folder', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
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
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.auto_awesome_rounded, size: 26, color: AppColors.brand),
            SizedBox(height: 6),
            Text('Refactor', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
            Text('Regroup all links', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ]),
        ),
      ),
    );
  }
}
