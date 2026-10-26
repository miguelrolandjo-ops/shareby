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
import 'sources.dart';
import 'thumbnail_store.dart';
import 'title_fetcher.dart';
import 'url_utils.dart';
import '../l10n/l10n.dart';

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
  Repository({required this.db, required this.sessions, Categorizer? categorizer, this.thumbs})
      : categorizer = categorizer ?? const KeywordCategorizer(threshold: AppConfig.suggestionThreshold);

  final LocalDb db;
  final SessionStore sessions;
  final Categorizer categorizer;

  /// Where each link's compressed picture is kept. null in tests that don't touch images.
  final ThumbnailStore? thumbs;

  /// After this many failed lookups the background timer stops retrying a link on its own.
  /// Opening the app and pull-to-refresh still try it again.
  static const maxFetchAttempts = 3;
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
      throw StateError(tr('Sign in with Google or Apple to create shared boards.'));
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
  ///
  /// [preview] is what the caller already looked up while the user was choosing. A link saved
  /// before any lookup finished has `fetched = false`, and the app finishes it later.
  Future<Item> addLink({
    required String url,
    String? title,
    String? folderId,
    String? author,
    PagePreview? preview,
  }) async {
    final now = _now();
    final user = sessions.current;
    var cleanTitle = (title == null || title.trim().isEmpty) ? fallbackTitle(url) : title.trim();
    var cleanAuthor = author;
    var found = preview;

    String? target;
    var status = 'confirmed';
    String? suggested;
    var confidence = 0.0;

    if (folderId == null) {
      // A bare link ("Saved from instagram.com") gives the categorizer nothing to
      // match, so look up the real page title first.
      if (isFallbackTitle(cleanTitle) && (found == null || !found.reached)) found = await fetchPagePreview(url);
      final text = isFallbackTitle(cleanTitle) ? (found?.title ?? cleanTitle) : cleanTitle;
      final suggestion = await suggestFor('$text $url', url: url);
      target = suggestion.folderId;
      suggested = suggestion.folderId;
      confidence = suggestion.confidence;
      status = 'new';
    } else if (folderId != kUncategorizedId) {
      final folder = await db.folderById(folderId);
      if (folder == null || folder.deleted) throw StateError(tr('That collection no longer exists.'));
      if (!folder.canAddLinks) throw StateError(tr('You can view this board but not add to it.'));
      target = folderId;
    }

    final reached = found != null && found.reached;
    if (reached) {
      if (isFallbackTitle(cleanTitle) && found.title != null) cleanTitle = found.title!;
      cleanAuthor ??= found.author;
    }
    final remoteImage = youtubeThumbnail(url) ?? (reached ? found.image : null);

    final item = Item(
      id: _uuid.v4(),
      folderId: target,
      url: url,
      title: cleanTitle,
      source: detectSource(url),
      author: cleanAuthor,
      // null = not looked up; '' = looked up, nothing there. The picture itself is downloaded
      // by the fetch queue right after saving.
      thumbnailUrl: remoteImage ?? (reached ? '' : null),
      fetched: reached,
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

  /// The fetch queue. One pass handles up to [limit] links and returns how many it tried
  /// (0 = nothing left), so callers loop until it reports 0.
  ///
  /// A link needs a **lookup** (its page's title, author and picture address) while it is not
  /// [Item.fetched], and a **download** (the picture, shrunk and kept on this device) while it
  /// has a picture address but no stored file. Both are retried here; saving offline or before
  /// a lookup finished just leaves the link `fetched = false`.
  ///
  ///  * [hard]: redo everything for the links in scope, even ones already fetched, replacing
  ///    their stored picture. Pull-to-refresh.
  ///  * [folderId]: limit the pass to one folder ([kUncategorizedId] for Uncategorized).
  ///  * [ignoreAttempts]: also retry links that already failed [maxFetchAttempts] times.
  ///  * [skip]: links not to try (recently tried); each link tried is added, so one run never
  ///    repeats itself.
  ///
  /// Only your own saves are looked up (edits to a friend's pin would be rejected); the
  /// pictures of friends' pins are still downloaded, since that is local only.
  Future<int> backfillPreviews(
    Set<String> skip, {
    int limit = 24,
    int concurrency = 6,
    bool hard = false,
    String? folderId,
    bool ignoreAttempts = false,
  }) async {
    final shared = {
      for (final f in await db.folders())
        if (f.isShared) f.id
    };
    final all = await db.items();
    if (skip.isEmpty) await thumbs?.sweep(all.map((i) => i.thumbPath).whereType<String>().toSet());

    bool inScope(Item i) =>
        folderId == null || (folderId == kUncategorizedId ? i.folderId == null : i.folderId == folderId);
    bool canTry(Item i) => hard || ignoreAttempts || i.fetchAttempts < maxFetchAttempts;
    bool hasPictureAddress(Item i) => i.thumbnailUrl != null && i.thumbnailUrl!.isNotEmpty;
    bool needsLookup(Item i) => !shared.contains(i.folderId) && (hard || !i.fetched);
    bool needsDownload(Item i) =>
        thumbs != null && hasPictureAddress(i) && (hard || thumbs!.fileFor(i.thumbPath) == null);

    final todo = all
        .where((i) => inScope(i) && !skip.contains(i.id) && canTry(i) && (needsLookup(i) || needsDownload(i)))
        .take(limit)
        .toList();
    skip.addAll(todo.map((i) => i.id));
    // A small worker pool: a slow site holds up one worker, not the whole batch.
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final item = todo[next++];
        try {
          await _refreshOne(item, lookup: needsLookup(item));
        } catch (_) {
          // One broken page must not stop the others.
        }
      }
    }

    await Future.wait([for (var w = 0; w < concurrency && w < todo.length; w++) worker()]);
    return todo.length;
  }

  Future<void> _refreshOne(Item item, {required bool lookup}) async {
    var failed = false;
    PagePreview? preview;
    if (lookup) {
      preview = await fetchPagePreview(item.url);
      // Offline or the site is temporarily down: leave it for next time.
      if (!preview.reached) failed = true;
    }
    final reached = preview != null && preview.reached;

    // Where the picture comes from: the link itself (YouTube), else the page's, else what we had.
    final had = item.thumbnailUrl ?? '';
    final String? pictureUrl;
    if (reached) {
      pictureUrl = youtubeThumbnail(item.url) ?? preview.image ?? had;
    } else {
      pictureUrl = had.isNotEmpty ? had : (youtubeThumbnail(item.url) ?? item.thumbnailUrl);
    }

    String? storedName;
    if (!failed && thumbs != null && pictureUrl != null && pictureUrl.isNotEmpty) {
      storedName = await thumbs!.save(item.id, pictureUrl);
      if (storedName == null) failed = true; // the page answered but the picture didn't: retry later
    }

    // Write onto the latest copy: the user may have edited the link while this ran.
    final fresh = await db.itemById(item.id);
    if (fresh == null || fresh.deleted) return;
    final newTitle = reached && preview.title != null && isFallbackTitle(fresh.title) ? preview.title : null;
    final newAuthor = reached && preview.author != null && fresh.author != preview.author ? preview.author : null;
    final addressChanged = reached && pictureUrl != fresh.thumbnailUrl;
    final synced = newTitle != null || newAuthor != null || addressChanged;

    final updated = fresh.copyWith(
      title: newTitle,
      author: newAuthor,
      thumbnailUrl: addressChanged ? pictureUrl : null,
      thumbPath: storedName,
      clearThumbPath: storedName == null && addressChanged, // the old file is of another picture
      fetched: reached ? true : null,
      fetchAttempts: failed ? fresh.fetchAttempts + 1 : 0,
      updatedAt: synced ? _now() : null,
    );
    if (synced) {
      await _saveItem(updated);
    } else {
      // Only device-local columns changed, so nothing to sync.
      await db.updateLocal(fresh.id, {
        'fetched': updated.fetched ? 1 : 0,
        'thumb_path': updated.thumbPath,
        'fetch_attempts': updated.fetchAttempts,
      });
    }
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
        final suggestion = await suggestFor('$title ${item.url}', url: item.url);
        final hit = suggestion.folderId != null;
        if (hit) matched++;
        await _saveItem(item.copyWith(
          title: preview.title,
          author: item.author == null ? preview.author : null,
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

  /// Auto-categorization only ever considers personal folders. [url], when given, lets the
  /// link's source count too (see [KeywordCategorizer.suggest]).
  Future<Suggestion> suggestFor(String text, {String? url}) async {
    final folders = (await db.folders()).where((f) => !f.isShared).toList();
    final items = await db.items();
    final catalog = SourceCatalog.current;
    final candidates = [
      for (final f in folders)
        () {
          final filed = items.where((i) => i.folderId == f.id && !i.isNew).take(25).toList();
          return CategoryCandidate(
            id: f.id,
            name: f.name,
            examples: [for (final i in filed) i.title],
            exampleSources: [for (final i in filed) catalog.keyOf(i)],
          );
        }(),
    ];
    return categorizer.suggest(text, candidates, source: url == null ? null : catalog.keyForUrl(url));
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
    if (undo == null) throw StateError(tr('There is nothing to undo, or it was more than 24 hours ago.'));
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
        throw StateError(tr('Tags are only available in your personal folders.'));
      }
    }
    final clean = tag?.trim() ?? '';
    await _saveItem(item.copyWith(
      tag: clean.isEmpty ? null : clean,
      clearTag: clean.isEmpty,
      updatedAt: _now(),
    ));
  }

  /// After the platform table changes (a new app version, or fresh rules from the server),
  /// links saved as plain web pages may now belong to a platform. Returns how many changed.
  Future<int> reclassifySources() async {
    var changed = 0;
    for (final item in await db.items()) {
      final now = detectSource(item.url);
      if (now == item.source) continue;
      await _saveItem(item.copyWith(source: now, updatedAt: _now()));
      changed++;
    }
    return changed;
  }

  /// Sets (or clears) one sub-category on several links at once. Personal folders only.
  Future<void> setTags(List<Item> items, String? tag) async {
    for (final item in items) {
      await setTag(item, tag);
    }
  }

  /// Puts [previous] back (e.g. undoing a quick confirm), as a fresh edit so it syncs.
  Future<void> restoreItem(Item previous) async {
    final current = await db.itemById(previous.id);
    if (current == null) return;
    await _saveItem(previous.copyWith(
      thumbPath: current.thumbPath,
      updatedAt: _now(),
    ));
  }

  Future<void> deleteItem(Item item) async {
    await _saveItem(item.copyWith(deleted: true, updatedAt: _now()));
    await thumbs?.delete(item.thumbPath);
  }

  /// Edits a link's title and address. Changing the address starts a fresh lookup: the old
  /// picture, author and platform no longer describe the page. A typed title is never
  /// cleaned or replaced by a lookup. On a shared board only the person who added the link
  /// (or the board's owner) can edit it, because the server only accepts edits from them.
  Future<Item> updateLink(Item item, {required String title, required String url}) async {
    await _requireCanEditContent(item);
    final cleanUrl = extractUrl(url);
    if (cleanUrl == null) throw StateError('Enter a link that starts with http:// or https://');
    final typed = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final newTitle = typed.isEmpty ? fallbackTitle(cleanUrl) : (typed.length > 300 ? typed.substring(0, 300) : typed);
    final moved = cleanUrl != item.url;
    if (!moved && newTitle == item.title) return item;

    final updated = item.copyWith(
      url: cleanUrl,
      title: newTitle,
      source: detectSource(cleanUrl),
      clearAuthor: moved,
      clearThumbnailUrl: moved,
      clearThumbPath: moved,
      fetched: moved ? false : null,
      fetchAttempts: moved ? 0 : null,
      updatedAt: _now(),
    );
    await _saveItem(updated);
    if (moved) await thumbs?.delete(item.thumbPath);
    return updated;
  }

  /// Pins a link to the top of its folder (or unpins it). Works in personal folders and, for
  /// editors, on shared boards, where the pin is shared with everyone. Only pin fields
  /// change, so it never conflicts with someone else's edit to the title or folder.
  Future<void> setPinned(Item item, bool pinned) async {
    if (item.isNew) throw StateError(tr('Confirm which folder this goes in first, then pin it.'));
    await _requireCanChange(item);
    final now = _now();
    final user = sessions.current;
    await _saveItem(pinned
        ? item.copyWith(
            completedAt: now,
            completedBy: user?.userId,
            completedByName: user?.displayName ?? 'You',
            completionUpdatedAt: now,
          )
        : item.copyWith(clearCompleted: true, completionUpdatedAt: now));
  }

  /// Undo for [setPinned]: puts back exactly who pinned it and when.
  Future<void> restorePin(Item current, Item previous) async {
    await _requireCanChange(current);
    await _saveItem(previous.completedAt == null
        ? current.copyWith(clearCompleted: true, completionUpdatedAt: _now())
        : current.copyWith(
            completedAt: previous.completedAt,
            completedBy: previous.completedBy,
            completedByName: previous.completedByName,
            completionUpdatedAt: _now(),
          ));
  }

  /// Changing a link's title or address is the author's right (the server enforces it too).
  Future<void> _requireCanEditContent(Item item) async {
    final me = sessions.current?.userId;
    if (me == null || item.folderId == null) return;
    final folder = await db.folderById(item.folderId!);
    if (folder == null || !folder.isShared) return;
    if (item.addedBy != me && folder.ownerId != me) {
      throw StateError(tr('Only the person who added this link can edit it.'));
    }
  }

  Future<void> _requireCanChange(Item item) async {
    if (item.folderId == null) return;
    final folder = await db.folderById(item.folderId!);
    if (folder != null && folder.isShared && !folder.canAddLinks) {
      throw StateError(tr('You can view this board but not change it.'));
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

    if (L10n.current != AppLanguage.id) {
      // English demo for every other region.
      final cooking = await folder('Cooking', FolderPalette.amber, '🍳');
      final city = await folder('City Weekend', FolderPalette.sky, '🏙️');
      final beach = await folder('Beach Trip', FolderPalette.mint, '🌴');
      final cafe = await folder('Cafe Picks', FolderPalette.coral, '☕');
      final sports = await folder('Workouts', FolderPalette.lilac, '🏀');

      await link(cooking, 'One-pan garlic butter pasta in 15 minutes', 'https://www.instagram.com/reel/shareby-demo-1',
          tag: 'Weeknight');
      await link(cooking, 'No-bake cheesecake that melts in your mouth', 'https://www.tiktok.com/@shareby/video/1001',
          tag: 'Dessert');
      await link(cooking, 'Meal prep for the whole week on a budget', 'https://www.instagram.com/reel/shareby-demo-2');
      await link(city, 'Rooftop bars with the best sunset views', 'https://www.instagram.com/p/shareby-demo-3',
          done: true);
      await link(city, 'A perfect day in the old town: full itinerary', 'https://www.youtube.com/watch?v=shareby0001',
          tag: 'Day trip');
      await link(beach, 'Sunrise hike worth waking up for', 'https://www.youtube.com/watch?v=shareby0002',
          tag: 'Must do');
      await link(beach, 'Cheap local food spots near the beach', 'https://www.instagram.com/reel/shareby-demo-4');
      await link(cafe, 'The best iced latte in town under \$5', 'https://www.instagram.com/reel/shareby-demo-5',
          tag: 'Budget');
      await link(sports, '15-minute home workout, no equipment', 'https://www.instagram.com/reel/shareby-demo-6');

      // Waiting in "Needs a quick look".
      await link(cooking, 'Crispy fried chicken with a spicy chili dip', 'https://www.youtube.com/watch?v=shareby0003',
          isNew: true);
      await link(cafe, 'Viral dessert box you have to try', 'https://www.tiktok.com/@shareby/video/1002', isNew: true);
      await link(city, 'Golden hour photo spots downtown', 'https://www.tiktok.com/@shareby/video/1003',
          isNew: true, views: 1);
      await sessions.markSeeded();
      return;
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
