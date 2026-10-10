import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/theme.dart';
import 'categorizer.dart';
import 'local_db.dart';
import 'models.dart';
import 'session_store.dart';
import 'url_utils.dart';

/// Every change the user makes goes through here.
///
/// Writes land in SQLite first, so the app works fully offline. When signed in,
/// each write also queues an outbox op in the same transaction; [SyncService]
/// pushes those to the server whenever it can reach it.
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

  /// Duplicate names are allowed; the copy gets " (2)", " (3)"... to tell them apart.
  Future<String> _uniqueName(String name, {required bool shared}) async {
    final taken = (await db.folders())
        .where((f) => f.isShared == shared)
        .map((f) => f.name.toLowerCase())
        .toSet();
    if (!taken.contains(name.toLowerCase())) return name;
    var n = 2;
    while (taken.contains('${name.toLowerCase()} ($n)')) {
      n++;
    }
    return '$name ($n)';
  }

  Future<void> updateFolder(Folder f, {String? name, int? color, String? emoji}) =>
      _save(f.copyWith(name: name?.trim(), color: color, emoji: emoji, updatedAt: _now()));

  /// Deleting a personal folder keeps its links: they move to Uncategorized.
  Future<void> deleteFolder(Folder f) async {
    final now = _now();
    await _save(f.copyWith(deleted: true, updatedAt: now));
    final inside = (await db.items()).where((i) => i.folderId == f.id);
    for (final item in inside) {
      await _saveItem(f.isShared
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
    final cleanTitle = (title == null || title.trim().isEmpty) ? fallbackTitle(url) : title.trim();

    String? target;
    var status = 'confirmed';
    String? suggested;
    var confidence = 0.0;

    if (folderId == null) {
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
      thumbnailUrl: youtubeThumbnail(url),
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

  /// Auto-categorization only ever considers personal folders.
  Future<Suggestion> suggestFor(String text) async {
    final folders = (await db.folders()).where((f) => !f.isShared).toList();
    final items = await db.items();
    final candidates = [
      for (final f in folders)
        CategoryCandidate(
          id: f.id,
          name: f.name,
          examples: items
              .where((i) => i.folderId == f.id && !i.isNew)
              .take(25)
              .map((i) => i.title)
              .toList(),
        ),
    ];
    return categorizer.suggest(text, candidates);
  }

  /// Confirms a [New] item, optionally into a different personal folder.
  Future<void> confirmItem(Item item, {String? moveTo}) async {
    final target = moveTo ?? item.folderId ?? kUncategorizedId;
    await _saveItem(item.copyWith(
      folderId: target == kUncategorizedId ? null : target,
      clearFolder: target == kUncategorizedId,
      status: 'confirmed',
      updatedAt: _now(),
    ));
  }

  Future<void> moveItem(Item item, String folderId) => confirmItem(item, moveTo: folderId);

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
      final f = Folder(id: _uuid.v4(), name: name, color: color, emoji: emoji, isShared: false,
          createdAt: t, updatedAt: t);
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

    await link(cooking, 'Resep nasi goreng cuma butuh 3 bahan', 'https://www.instagram.com/reel/shareby-demo-1', tag: 'Jumat gas');
    await link(cooking, 'Cheesecake no-bake yang lumer di mulut', 'https://www.tiktok.com/@shareby/video/1001', tag: 'Dessert');
    await link(cooking, 'Cara bikin bumbu rendang tahan lama', 'https://www.instagram.com/reel/shareby-demo-2');
    await link(jakarta, 'Rooftop bar Senopati buat nongkrong malam', 'https://www.instagram.com/p/shareby-demo-3', done: true);
    await link(jakarta, 'Itinerary sehari muter Kota Tua', 'https://www.youtube.com/watch?v=shareby0001', tag: 'Day trip');
    await link(bali, 'Sunrise trek Gunung Batur worth it banget', 'https://www.youtube.com/watch?v=shareby0002', tag: 'Must do');
    await link(bali, 'Warung lokal murah enak di Canggu', 'https://www.instagram.com/reel/shareby-demo-4');
    await link(cafe, 'Kopi susu terenak murah di Kemang', 'https://www.instagram.com/reel/shareby-demo-5', tag: 'Under 25rb');
    await link(sports, 'Home workout 15 menit tanpa alat', 'https://www.instagram.com/reel/shareby-demo-6');

    // Waiting in "Needs a quick look", as in the prototype.
    await link(cooking, 'Ayam geprek sambel korek pedas nampol', 'https://www.youtube.com/watch?v=shareby0003', isNew: true);
    await link(cafe, 'Dessert box viral yang wajib dicoba', 'https://www.tiktok.com/@shareby/video/1002', isNew: true);
    await link(jakarta, 'Spot foto golden hour di GBK', 'https://www.tiktok.com/@shareby/video/1003', isNew: true, views: 1);

    await sessions.markSeeded();
  }
}
