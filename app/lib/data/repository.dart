import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/theme.dart';
import 'categorizer.dart';
import 'folder_namer.dart';
import 'local_db.dart';
import 'models.dart';
import 'refactor_planner.dart';
import 'refactor_undo.dart';
import 'session_store.dart';
import 'title_fetcher.dart';
import 'url_utils.dart';

/// Every change the user makes goes through here.
///
/// Writes land in SQLite first, so the app works fully offline. When signed in,
/// each write also queues an outbox op in the same transaction; [SyncService]
/// pushes those to the server whenever it can reach it.
class RetryResult {
  const RetryResult({required this.matched, required this.unmatched});

  final int matched;
  final int unmatched;
}

class Repository {
  Repository({required this.db, required this.sessions, Categorizer? categorizer})
      : categorizer = categorizer ?? const KeywordCategorizer(threshold: AppConfig.suggestionThreshold);

  final LocalDb db;
  final SessionStore sessions;
  final Categorizer categorizer;
  final _uuid = Uuid();

  DateTime _now() => DateTime.now().toUtc();

  /// Only queue for sync once there is an account to sync to.
  String? get _opId => sessions.isSignedIn ? _uuid.v4() : null;

  Future<void> _save(Folder f) => db.saveFolder(f, enqueueOpId: _opId);
  Future<void> _saveItem(Item i) => db.saveItem(i, enqueueOpId: _opId);

  // -------------------------------------------------------------- folders

  Future<Folder> createFolder({
    required String name,
    required int color,
    required String emoji,
    bool isShared = false,
  }) async {
    if (isShared && !sessions.isSignedIn) {
      throw StateError('Sign in with Google or Apple to create shared boards.');
    }
    final now = _now();
    final user = sessions.current;
    final folder = Folder(
      id: _uuid.v4(),
      name: await _uniqueName(name.trim(), shared: isShared),
      color: color,
      emoji: emoji,
      isShared: isShared,
      ownerId: user?.userId,
      myRole: 'owner',
      createdAt: now,
      updatedAt: now,
    );
    await _save(folder);
    return folder;
  }

  /// "Auto create suggested folder": returns an existing personal folder that already
  /// covers this link's topic, or creates a new broad one (e.g. "K-Pop") for it.
  Future<Folder> autoFolderFor({required String url, String? title}) async {
    var text = (title ?? '').trim();
    if (text.isEmpty || isFallbackTitle(text)) {
      text = await fetchPageTitle(url) ?? text;
    }
    final folders = (await db.folders()).where((f) => !f.isShared && !f.deleted).toList();
    final proposal = const FolderNamer().propose('$text $url', {for (final f in folders) f.id: f.name});

    if (proposal.existingId != null) {
      return folders.firstWhere((f) => f.id == proposal.existingId);
    }
    final used = folders.map((f) => f.color).toSet();
    final color = FolderPalette.all.firstWhere((c) => !used.contains(c),
        orElse: () => FolderPalette.all[folders.length % FolderPalette.all.length]);
    return createFolder(name: proposal.name, color: color, emoji: proposal.emoji);
  }

  /// Duplicate names are allowed; the copy gets " (2)", " (3)"... to tell them apart.
  Future<String> _uniqueName(String name, {required bool shared}) async {
    final taken = (await db.folders()).where((f) => f.isShared == shared).map((f) => f.name.toLowerCase()).toSet();
    if (!taken.contains(name.toLowerCase())) return name;
    var n = 2;
    while (taken.contains('${name.toLowerCase()} ($n)')) {
      n++;
    }
    return '$name ($n)';
  }

  Future<void> updateFolder(Folder f, {String? name, int? color, String? emoji}) =>
      _save(f.copyWith(name: name?.trim(), color: color, emoji: emoji, updatedAt: _now()));

  /// Deleting a folder. Personal folders: the links inside are deleted too (default), or
  /// kept and moved to Uncategorized when [keepLinks] is true. Shared boards always
  /// remove their pins.
  Future<void> deleteFolder(Folder f, {bool keepLinks = false}) async {
    final now = _now();
    await _save(f.copyWith(deleted: true, updatedAt: now));
    final inside = (await db.items()).where((i) => i.folderId == f.id);
    for (final item in inside) {
      await _saveItem(f.isShared || !keepLinks
          ? item.copyWith(deleted: true, updatedAt: now)
          : item.copyWith(clearFolder: true, status: 'confirmed', updatedAt: now));
    }
  }

  // ---------------------------------------------------------------- items

  /// Adds a link.
  ///  * [folderId] == null -> "save now, sort later": auto-suggest a personal folder, mark [New].
  ///  * [folderId] == [kUncategorizedId] -> keep it in Uncategorized.
  ///  * otherwise -> straight into that folder (personal or shared board).
  Future<Item> addLink({required String url, String? title, String? folderId}) async {
    final now = _now();
    final user = sessions.current;
    var cleanTitle = (title == null || title.trim().isEmpty) ? fallbackTitle(url) : title.trim();

    String? target;
    var status = 'confirmed';
    String? suggested;
    var confidence = 0.0;
    String? previewImage;
    var fetchedNow = false;

    if (folderId == null) {
      // A bare link ("Saved from instagram.com") gives the categorizer nothing to
      // match, so look up the real page title first.
      if (isFallbackTitle(cleanTitle)) {
        final preview = await fetchPagePreview(url);
        if (preview.title != null) cleanTitle = preview.title!;
        previewImage = preview.image;
        fetchedNow = preview.reached;
      }
      final suggestion = await suggestFor('$cleanTitle $url');
      target = suggestion.folderId;
      suggested = suggestion.folderId;
      confidence = suggestion.confidence;
      status = 'new';
    } else if (folderId != kUncategorizedId) {
      final folder = await db.folderById(folderId);
      if (folder == null || folder.deleted) throw StateError('That collection no longer exists.');
      if (!folder.canAddLinks) throw StateError('You can view this board but not add to it.');
      target = folderId;
    }

    final item = Item(
      id: _uuid.v4(),
      folderId: target,
      url: url,
      title: cleanTitle,
      source: detectSource(url),
      thumbnailUrl: youtubeThumbnail(url) ?? previewImage ?? (fetchedNow ? '' : null),
      fetched: fetchedNow,
      status: status,
      suggestedFolderId: suggested,
      confidence: confidence,
      addedBy: user?.userId,
      addedByName: user?.displayName,
      createdAt: now,
      updatedAt: now,
    );
    await _saveItem(item);
    return item;
  }

  /// Looks up every link that is not [Item.fetched] yet: the page's real title (where the
  /// link only had a placeholder) and its thumbnail. A link is marked fetched only when the
  /// site answered, so ones saved offline stay unfetched and are retried next time.
  /// Personal saves only: edits to a board you can only view would be rejected.
  ///
  /// [skip] holds links not to try (recently tried); each link tried is added to it, so one
  /// run never repeats itself. Returns how many links were tried (0 = nothing left to do).
  Future<int> backfillPreviews(Set<String> skip, {int limit = 6}) async {
    final shared = {
      for (final f in await db.folders())
        if (f.isShared) f.id
    };
    final todo = (await db.items())
        .where((i) => !i.fetched && !skip.contains(i.id) && !shared.contains(i.folderId))
        .take(limit)
        .toList();
    skip.addAll(todo.map((i) => i.id));
    final previews = await Future.wait([for (final item in todo) fetchPagePreview(item.url)]);
    for (var n = 0; n < todo.length; n++) {
      final item = todo[n];
      final preview = previews[n];
      if (!preview.reached) continue; // offline or temporarily down: leave it for next time
      final hasThumb = item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty;
      await _saveItem(item.copyWith(
        fetched: true,
        thumbnailUrl: hasThumb ? null : (youtubeThumbnail(item.url) ?? preview.image ?? ''),
        title: isFallbackTitle(item.title) ? preview.title : null,
        updatedAt: _now(),
      ));
    }
    return todo.length;
  }

  /// Uncategorized "Refactor": tries every link there against your folders once more.
  ///  * a match becomes a [New] suggestion, like any fresh save, so you can confirm it;
  ///  * no match stays in Uncategorized and is marked confirmed, so it raises no "new item"
  ///    notification again.
  /// Links that only have a placeholder title get their real title looked up first.
  Future<RetryResult> retryUncategorized() async {
    final stuck = (await db.items()).where((i) => i.folderId == null).toList();
    var matched = 0;
    // Look up titles a few at a time; each lookup is network-bound.
    for (var start = 0; start < stuck.length; start += 4) {
      final batch = stuck.skip(start).take(4).toList();
      final previews = await Future.wait([
        for (final item in batch)
          isFallbackTitle(item.title) ? fetchPagePreview(item.url) : Future.value(const PagePreview()),
      ]);
      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        final preview = previews[i];
        final title = preview.title ?? item.title;
        final suggestion = await suggestFor('$title ${item.url}');
        final hit = suggestion.folderId != null;
        if (hit) matched++;
        await _saveItem(item.copyWith(
          title: preview.title,
          thumbnailUrl: item.thumbnailUrl == null ? preview.image : null,
          fetched: preview.reached ? true : null,
          folderId: suggestion.folderId,
          suggestedFolderId: suggestion.folderId,
          confidence: suggestion.confidence,
          status: hit ? 'new' : 'confirmed',
          viewCount: hit ? 0 : null,
          updatedAt: _now(),
        ));
      }
    }
    return RetryResult(matched: matched, unmatched: stuck.length - matched);
  }

  /// Auto-categorization only ever considers personal folders.
  Future<Suggestion> suggestFor(String text) async {
    final folders = (await db.folders()).where((f) => !f.isShared).toList();
    final items = await db.items();
    final candidates = [
      for (final f in folders)
        CategoryCandidate(
          id: f.id,
          name: f.name,
          examples: items.where((i) => i.folderId == f.id && !i.isNew).take(25).map((i) => i.title).toList(),
        ),
    ];
    return categorizer.suggest(text, candidates);
  }

  /// Confirms a [New] item, optionally into a different personal folder.
  Future<void> confirmItem(Item item, {String? moveTo}) async {
    final target = moveTo ?? item.folderId ?? kUncategorizedId;
    final changesFolder = target != (item.folderId ?? kUncategorizedId);
    await _saveItem(item.copyWith(
      folderId: target == kUncategorizedId ? null : target,
      clearFolder: target == kUncategorizedId,
      clearTag: changesFolder, // a sub-category belongs to one folder
      status: 'confirmed',
      updatedAt: _now(),
    ));
  }

  Future<void> moveItem(Item item, String folderId) => confirmItem(item, moveTo: folderId);

  /// Mass edit: move several links to one personal folder (or Uncategorized).
  Future<void> moveItems(List<Item> items, String folderId) async {
    for (final item in items) {
      await confirmItem(item, moveTo: folderId);
    }
  }

  Future<void> deleteItems(List<Item> items) async {
    for (final item in items) {
      await deleteItem(item);
    }
  }

  /// Manual order of the folders on Home (ids in display order). Stays on this device.
  Future<void> setFolderOrder(List<String> idsInOrder) => db.setFolderSortOrders(idsInOrder);

  /// Manual order inside a folder (ids in display order). Stays on this device.
  Future<void> setItemOrder(List<String> idsInOrder) => db.setSortOrders(idsInOrder);

  /// Applies a reviewed [RefactorPlan]: creates (or reuses) a personal folder per group,
  /// moves the links in, then removes old personal folders left empty.
  Future<int> applyRefactor(RefactorPlan plan) async {
    final items = {for (final i in await db.items()) i.id: i};
    final folders = (await db.folders()).where((f) => !f.isShared && !f.deleted).toList();
    final touchedFolderIds = <String>{};
    final before = <ItemBefore>[];
    final createdIds = <String>[];
    final removedIds = <String>[];
    var moved = 0;
    var colorIndex = 0;

    for (final group in plan.groups) {
      final members = [
        for (final id in group.itemIds)
          if (items[id] != null) items[id]!
      ];
      if (members.isEmpty) continue;
      final existing = folders.where((f) => f.name.toLowerCase() == group.name.toLowerCase());
      final Folder target = existing.isNotEmpty
          ? existing.first
          : await createFolder(
              name: group.name,
              color: FolderPalette.all[colorIndex++ % FolderPalette.all.length],
              emoji: group.emoji,
            );
      if (existing.isEmpty) createdIds.add(target.id);
      for (final item in members) {
        if (item.folderId == target.id) continue;
        if (item.folderId != null) touchedFolderIds.add(item.folderId!);
        before.add(ItemBefore(id: item.id, folderId: item.folderId, status: item.status, tag: item.tag));
        await confirmItem(item, moveTo: target.id);
        moved++;
      }
    }

    // An old folder that the refactor emptied has nothing left to hold.
    final remaining = await db.items();
    for (final f in folders) {
      if (touchedFolderIds.contains(f.id) && !remaining.any((i) => i.folderId == f.id)) {
        await _save(f.copyWith(deleted: true, updatedAt: _now()));
        removedIds.add(f.id);
      }
    }
    if (before.isNotEmpty || createdIds.isNotEmpty) {
      await sessions.setRefactorUndoRaw(jsonEncode(RefactorUndo(
        at: DateTime.now(),
        items: before,
        createdFolderIds: createdIds,
        removedFolderIds: removedIds,
      ).toJson()));
    }
    return moved;
  }

  /// The last refactor, if it can still be undone (within 24 hours).
  RefactorUndo? get refactorUndo {
    final raw = sessions.refactorUndoRaw;
    if (raw == null) return null;
    try {
      final undo = RefactorUndo.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      if (!undo.isExpired()) return undo;
    } catch (_) {
      // A damaged snapshot is as good as none.
    }
    sessions.setRefactorUndoRaw(null);
    return null;
  }

  /// Puts every link back where it was, brings back the folders the refactor removed and
  /// removes the ones it created (links added to those since go to Uncategorized).
  Future<int> undoRefactor() async {
    final undo = refactorUndo;
    if (undo == null) throw StateError('There is nothing to undo, or it was more than 24 hours ago.');
    final now = _now();

    for (final id in undo.removedFolderIds) {
      final f = await db.folderById(id);
      if (f != null && f.deleted) await _save(f.copyWith(deleted: false, updatedAt: now));
    }

    final live = {for (final f in await db.folders()) f.id};
    final items = {for (final i in await db.items()) i.id: i};
    var restored = 0;
    for (final b in undo.items) {
      final item = items[b.id];
      if (item == null) continue; // deleted since
      final home = (b.folderId != null && live.contains(b.folderId)) ? b.folderId : null;
      await _saveItem(item.copyWith(
        folderId: home,
        clearFolder: home == null,
        status: b.status,
        tag: b.tag,
        clearTag: b.tag == null,
        updatedAt: now,
      ));
      restored++;
    }

    final stillInside = await db.items();
    for (final id in undo.createdFolderIds) {
      for (final item in stillInside.where((i) => i.folderId == id)) {
        await _saveItem(item.copyWith(clearFolder: true, status: 'confirmed', updatedAt: now));
      }
      final f = await db.folderById(id);
      if (f != null && !f.deleted) await _save(f.copyWith(deleted: true, updatedAt: now));
    }

    await sessions.setRefactorUndoRaw(null);
    return restored;
  }

  /// Tags are a personal-folder feature; shared boards are curated together without them.
  Future<void> setTag(Item item, String? tag) async {
    if (item.folderId != null) {
      final folder = await db.folderById(item.folderId!);
      if (folder != null && folder.isShared) {
        throw StateError('Tags are only available in your personal folders.');
      }
    }
    final clean = tag?.trim() ?? '';
    await _saveItem(item.copyWith(
      tag: clean.isEmpty ? null : clean,
      clearTag: clean.isEmpty,
      updatedAt: _now(),
    ));
  }

  Future<void> deleteItem(Item item) => _saveItem(item.copyWith(deleted: true, updatedAt: _now()));

  /// Ticks a link done (or not). Works in personal folders and, for editors, on shared
  /// boards, where it is shared with everyone. Only completion fields change, so it never
  /// conflicts with someone else's edit to the title or folder.
  Future<void> setDone(Item item, bool done) async {
    if (item.isNew) throw StateError('Confirm which folder this goes in first, then mark it done.');
    await _requireCanChange(item);
    final now = _now();
    final user = sessions.current;
    await _saveItem(done
        ? item.copyWith(
            completedAt: now,
            completedBy: user?.userId,
            completedByName: user?.displayName ?? 'You',
            completionUpdatedAt: now,
          )
        : item.copyWith(clearCompleted: true, completionUpdatedAt: now));
  }

  /// Undo for [setDone]: puts back exactly who ticked it and when.
  Future<void> restoreCompletion(Item current, Item previous) async {
    await _requireCanChange(current);
    await _saveItem(Item(
      id: current.id,
      folderId: current.folderId,
      url: current.url,
      title: current.title,
      source: current.source,
      thumbnailUrl: current.thumbnailUrl,
      tag: current.tag,
      status: current.status,
      suggestedFolderId: current.suggestedFolderId,
      confidence: current.confidence,
      viewCount: current.viewCount,
      sortOrder: current.sortOrder,
      fetched: current.fetched,
      addedBy: current.addedBy,
      addedByName: current.addedByName,
      completedAt: previous.completedAt,
      completedBy: previous.completedBy,
      completedByName: previous.completedByName,
      completionUpdatedAt: _now(),
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      deleted: current.deleted,
    ));
  }

  Future<void> _requireCanChange(Item item) async {
    if (item.folderId == null) return;
    final folder = await db.folderById(item.folderId!);
    if (folder != null && folder.isShared && !folder.canAddLinks) {
      throw StateError('You can view this board but not change it.');
    }
  }

  /// Call when [New] items are shown. An item already shown
  /// [AppConfig.autoConfirmAfterViews] times without confirmation is confirmed now.
  /// Returns how many items were auto-confirmed.
  Future<int> registerImpressions() async {
    final newItems = (await db.items()).where((i) => i.isNew);
    var confirmed = 0;
    for (final item in newItems) {
      if (item.viewCount >= AppConfig.autoConfirmAfterViews) {
        await confirmItem(item);
        confirmed++;
      } else {
        await db.setViewCount(item.id, item.viewCount + 1);
      }
    }
    return confirmed;
  }

  /// First sign-in: queue everything saved on this device so it moves to the cloud.
  Future<void> enqueueFullUpload() async {
    for (final f in await db.folders()) {
      await db.saveFolder(f, enqueueOpId: _uuid.v4());
    }
    for (final i in await db.items()) {
      await db.saveItem(i, enqueueOpId: _uuid.v4());
    }
  }

  // ------------------------------------------------------------ demo seed

  /// The collections from the prototype, so a fresh install isn't empty.
  Future<void> seedIfNeeded() async {
    if (!AppConfig.seedDemoData || sessions.seeded || !await db.isEmpty()) {
      await sessions.markSeeded();
      return;
    }
    final base = _now().subtract(const Duration(days: 3));
    var tick = 0;
    DateTime at() => base.add(Duration(minutes: tick++));

    Future<Folder> folder(String name, int color, String emoji) async {
      final t = at();
      final f =
          Folder(id: _uuid.v4(), name: name, color: color, emoji: emoji, isShared: false, createdAt: t, updatedAt: t);
      await db.saveFolder(f);
      return f;
    }

    Future<void> link(Folder? f, String title, String url,
        {String? tag, bool isNew = false, int views = 0, bool done = false}) async {
      final t = at();
      await db.saveItem(Item(
        id: _uuid.v4(),
        folderId: f?.id,
        url: url,
        title: title,
        source: detectSource(url),
        tag: tag,
        status: isNew ? 'new' : 'confirmed',
        suggestedFolderId: isNew ? f?.id : null,
        confidence: isNew ? 0.72 : 0,
        viewCount: views,
        completedAt: done ? t : null,
        completedByName: done ? 'You' : null,
        completionUpdatedAt: done ? t : null,
        createdAt: t,
        updatedAt: t,
      ));
    }

    final cooking = await folder('Cooking', FolderPalette.amber, '🍳');
    final jakarta = await folder('Jakarta Trip', FolderPalette.sky, '🏙️');
    final bali = await folder('Bali Trip', FolderPalette.mint, '🌴');
    final cafe = await folder('Cafe Picks', FolderPalette.coral, '☕');
    final sports = await folder('Sports Vibe', FolderPalette.lilac, '🏀');

    await link(cooking, 'Resep nasi goreng cuma butuh 3 bahan', 'https://www.instagram.com/reel/shareby-demo-1',
        tag: 'Jumat gas');
    await link(cooking, 'Cheesecake no-bake yang lumer di mulut', 'https://www.tiktok.com/@shareby/video/1001',
        tag: 'Dessert');
    await link(cooking, 'Cara bikin bumbu rendang tahan lama', 'https://www.instagram.com/reel/shareby-demo-2');
    await link(jakarta, 'Rooftop bar Senopati buat nongkrong malam', 'https://www.instagram.com/p/shareby-demo-3',
        done: true);
    await link(jakarta, 'Itinerary sehari muter Kota Tua', 'https://www.youtube.com/watch?v=shareby0001',
        tag: 'Day trip');
    await link(bali, 'Sunrise trek Gunung Batur worth it banget', 'https://www.youtube.com/watch?v=shareby0002',
        tag: 'Must do');
    await link(bali, 'Warung lokal murah enak di Canggu', 'https://www.instagram.com/reel/shareby-demo-4');
    await link(cafe, 'Kopi susu terenak murah di Kemang', 'https://www.instagram.com/reel/shareby-demo-5',
        tag: 'Under 25rb');
    await link(sports, 'Home workout 15 menit tanpa alat', 'https://www.instagram.com/reel/shareby-demo-6');

    // Waiting in "Needs a quick look", as in the prototype.
    await link(cooking, 'Ayam geprek sambel korek pedas nampol', 'https://www.youtube.com/watch?v=shareby0003',
        isNew: true);
    await link(cafe, 'Dessert box viral yang wajib dicoba', 'https://www.tiktok.com/@shareby/video/1002', isNew: true);
    await link(jakarta, 'Spot foto golden hour di GBK', 'https://www.tiktok.com/@shareby/video/1003',
        isNew: true, views: 1);

    await sessions.markSeeded();
  }
}
