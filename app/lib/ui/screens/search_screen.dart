import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/confirm_item_sheet.dart';
import '../sheets/item_actions_sheet.dart';
import '../widgets/item_tiles.dart';

/// Searches titles, links, tags and folder names on the device, so it works offline.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final words = _query.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final results = words.isEmpty
        ? const <Item>[]
        : state.allItems.where((item) {
            final folder = state.folderById(item.folderId ?? kUncategorizedId);
            final haystack = [item.title, item.url, item.tag ?? '', folder?.name ?? '', item.addedByName ?? '']
                .join(' ')
                .toLowerCase();
            return words.every(haystack.contains);
          }).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text('Search', style: headStyle(26)),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Try "sambal", "bali" or a friend\'s name',
                prefixIcon: const Icon(Icons.search_rounded),
                fillColor: AppColors.surface,
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (words.isNotEmpty && results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Text('Nothing matches "${_query.text.trim()}". Try a shorter word.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
              ),
            for (final item in results)
              Builder(builder: (context) {
                final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
                return ItemTile(
                  item: item,
                  color: Color(folder.color),
                  shared: folder.isShared,
                  folderLabel: '${folder.emoji} ${folder.name}',
                  onTap: () => item.isNew ? showConfirmItemSheet(context, item) : openLink(context, item.url),
                  onLongPress: () => showItemActions(context, item),
                  onToggleDone: state.canMarkDone(item) ? () => toggleDone(context, item) : null,
                );
              }),
          ],
        ),
      ),
    );
  }
}
