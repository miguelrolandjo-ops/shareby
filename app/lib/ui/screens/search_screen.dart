import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/platforms.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/confirm_item_sheet.dart';
import '../sheets/item_actions_sheet.dart';
import '../sheets/item_detail_dialog.dart';
import '../widgets/item_tiles.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';

enum _Sort { newest, oldest, title, mostViewed }

enum _DateRange { any, today, week, month, year }

Map<_Sort, String> get _sortLabels => {
      _Sort.newest: tr('Newest first'),
      _Sort.oldest: tr('Oldest first'),
      _Sort.title: tr('Title A–Z'),
      _Sort.mostViewed: tr('Most viewed'),
    };

Map<_DateRange, String> get _dateLabels => {
      _DateRange.any: tr('Any time'),
      _DateRange.today: tr('Today'),
      _DateRange.week: tr('Past 7 days'),
      _DateRange.month: tr('Past 30 days'),
      _DateRange.year: tr('Past year'),
    };

/// Searches titles, links, tags and folder names on the device, so it works offline.
/// With no query or filter it lists every link, newest first, as a grid.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  bool _pinnedOnly = false;
  bool _grid = true;
  _Sort _sort = _Sort.newest;
  _DateRange _date = _DateRange.any;
  Set<String> _sources = {};

  // Results appear a page at a time (7 grid rows, about 3 screens tall) and grow on scroll.
  static const _pageSize = 14;
  int _limit = _pageSize;
  String _signature = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  int get _filterCount => (_date == _DateRange.any ? 0 : 1) + (_sources.isEmpty ? 0 : 1);

  DateTime? _since() {
    final now = DateTime.now();
    return switch (_date) {
      _DateRange.any => null,
      _DateRange.today => DateTime(now.year, now.month, now.day),
      _DateRange.week => now.subtract(const Duration(days: 7)),
      _DateRange.month => now.subtract(const Duration(days: 30)),
      _DateRange.year => now.subtract(const Duration(days: 365)),
    };
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in _Sort.values)
            ListTile(
              title: Text(_sortLabels[s]!),
              trailing: s == _sort ? const Icon(Icons.check_rounded, color: AppColors.brand) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Future<void> _pickFilter() async {
    var date = _date;
    var sources = {..._sources};
    final options = [
      for (final s in SourceCatalog.current.filterOptions) (s.key, s.name),
      (PlatformRules.web, tr('Web')),
    ];
    final apply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Date added'), style: headStyle(16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in _DateRange.values) _chip(_dateLabels[d]!, date == d, () => setSheet(() => date = d)),
              ]),
              const SizedBox(height: 18),
              Text(tr('Source'), style: headStyle(16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (key, name) in options)
                  _chip(name, sources.contains(key),
                      () => setSheet(() => sources.contains(key) ? sources.remove(key) : sources.add(key))),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setSheet(() {
                      date = _DateRange.any;
                      sources = {};
                    }),
                    child: Text(tr('Clear')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Apply')))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (apply == true) {
      setState(() {
        _date = date;
        _sources = sources;
      });
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : AppColors.ink),
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
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final words = _query.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final since = _since();

    final results = state.allItems.where((item) {
      if (_pinnedOnly && !item.isPinned) return false;
      if (since != null && item.createdAt.isBefore(since)) return false;
      if (_sources.isNotEmpty && !_sources.contains(SourceCatalog.current.keyOf(item))) return false;
      if (words.isEmpty) return true;
      final folder = state.folderById(item.folderId ?? kUncategorizedId);
      final haystack = [item.title, item.url, item.tag ?? '', folder?.name ?? '', item.addedByName ?? '']
          .join(' ')
          .toLowerCase();
      return words.every(haystack.contains);
    }).toList()
      ..sort((a, b) => switch (_sort) {
            _Sort.newest => b.createdAt.compareTo(a.createdAt),
            _Sort.oldest => a.createdAt.compareTo(b.createdAt),
            _Sort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            _Sort.mostViewed => b.viewCount.compareTo(a.viewCount),
          });
    final filtering = words.isNotEmpty || _pinnedOnly || _filterCount > 0;
    final me = state.user?.userId;

    // Any change to the query, filters or sort starts again from the first page.
    final signature = '${_query.text}|$_pinnedOnly|$_sort|$_date|${_sources.join(",")}';
    if (signature != _signature) {
      _signature = signature;
      _limit = _pageSize;
    }
    final shown = results.length < _limit ? results.length : _limit;

    void open(Item item) => item.isNew ? showConfirmItemSheet(context, item) : showItemDetail(context, item);

    Widget cardAt(BuildContext context, int i) {
      final item = results[i];
      final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
      return ItemGridCard(
        item: item,
        color: Color(folder.color),
        shared: folder.isShared,
        pinLabel: pinnedByLabel(item, me),
        onTap: () => open(item),
        onLongPress: () => showItemActions(context, item),
      );
    }

    Widget tileAt(BuildContext context, int i) {
      final item = results[i];
      final folder = state.folderById(item.folderId ?? kUncategorizedId) ?? Folder.uncategorized();
      return ItemTile(
        item: item,
        color: Color(folder.color),
        shared: folder.isShared,
        folderLabel: '${folder.emoji} ${folder.name}',
        onTap: () => open(item),
        onLongPress: () => showItemActions(context, item),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: state.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Load the next page once the user is within one screen of the end.
              if (shown < results.length && n.metrics.extentAfter < n.metrics.viewportDimension) {
                setState(() => _limit += _pageSize);
              }
              return false;
            },
            child: CustomScrollView(
              // Always pullable, even when the results fit on screen.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(tr('Search'), style: headStyle(26)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _query,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: tr('Try "sambal", "bali" or a friend\'s name'),
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
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _chip(tr('Pinned'), _pinnedOnly, () => setState(() => _pinnedOnly = !_pinnedOnly),
                              icon: Icons.push_pin_rounded),
                          const SizedBox(width: 8),
                          _chip('Sort: ${_sortLabels[_sort]}', _sort != _Sort.newest, _pickSort,
                              icon: Icons.sort_rounded),
                          const SizedBox(width: 8),
                          _chip(_filterCount == 0 ? tr('Filter') : 'Filter ($_filterCount)', _filterCount > 0, _pickFilter,
                              icon: Icons.filter_list_rounded),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: _grid ? tr('Show as list') : tr('Show as grid'),
                            onPressed: () => setState(() => _grid = !_grid),
                            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                if (results.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Text(
                        filtering ? tr('Nothing matches. Try a shorter word or clear a filter.') : tr('No links saved yet.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  )
                else if (_grid)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      delegate: SliverChildBuilderDelegate(cardAt, childCount: shown),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(delegate: SliverChildBuilderDelegate(tileAt, childCount: shown)),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 40,
                    child: shown < results.length
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
