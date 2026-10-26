import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import '../data/platforms.dart';
import '../data/refactor_planner.dart';
import '../data/refactor_undo.dart';
import '../data/repository.dart';
import '../data/regions.dart';
import '../data/session_store.dart';
import '../data/settings_store.dart';
import '../data/sources.dart';
import '../data/share_intake.dart';
import '../data/sync_service.dart';
import '../data/title_fetcher.dart';
import '../data/url_utils.dart';
import '../l10n/l10n.dart';

/// What the sync indicator shows.
enum SyncState {
  /// Not signed in: everything lives on this device only.
  localOnly,
  syncing,
  synced,

  /// Signed in, but the server can't be reached. Edits keep queueing.
  offline,
  error,
}

/// The single object the UI watches. Reads come from SQLite snapshots held in memory;
/// every action writes locally first, refreshes the UI, then schedules a sync.
class AppState extends ChangeNotifier {
  AppState({
    required this.db,
    required this.repo,
    required this.sync,
    required this.auth,
    required this.sessions,
    required this.api,
    required this.shareIntake,
    required this.settings,
  });

  final LocalDb db;
  final Repository repo;
  final SyncService sync;
  final AuthService auth;
  final SessionStore sessions;
  final ApiClient api;
  final ShareIntake shareIntake;
  final SettingsStore settings;

  List<Folder> _folders = const [];
  List<Item> _items = const [];
  List<Member> _members = const [];

  SyncState syncState = SyncState.localOnly;

  /// True while a pull-to-refresh is working in the background (the thin bar at the top).
  bool refreshing = false;
  String? syncMessage;
  DateTime? lastSyncedAt;
  int pendingChanges = 0;

  final List<PendingShare> _chooseQueue = [];
  final List<String> _flashes = [];
  Timer? _periodic;
  Timer? _debounce;
  DateTime? _lastImpressions;
  bool _disposed = false;

  // ---------------------------------------------------------------- reads

  UserSession? get user => sessions.current;
  bool get signedIn => sessions.isSignedIn;

  List<Folder> get personalFolders => _folders.where((f) => !f.isShared).toList();
  List<Folder> get sharedFolders => _folders.where((f) => f.isShared).toList();
  List<Item> get allItems => _items;
  List<Item> get newItems => _items.where((i) => i.isNew).toList();
  bool get hasUncategorized => _items.any((i) => i.folderId == null);

  Folder? folderById(String? id) {
    if (id == null) return null;
    if (id == kUncategorizedId) return Folder.uncategorized();
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Items in a folder, including [New] items suggested into it. Pinned links come first,
  /// most recently pinned on top; the rest keep their usual order.
  List<Item> itemsIn(String folderId) {
    final inside = folderId == kUncategorizedId
        ? _items.where((i) => i.folderId == null)
        : _items.where((i) => i.folderId == folderId);
    final pinned = inside.where((i) => i.isPinned).toList()
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return [...pinned, ...inside.where((i) => !i.isPinned)];
  }

  List<Member> membersOf(String folderId) => _members.where((m) => m.folderId == folderId).toList();

  Item? itemById(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Confirmed links in personal folders, or on boards where you can add pins.
  bool canPin(Item item) {
    if (item.isNew) return false;
    final folder = folderById(item.folderId);
    return folder == null || !folder.isShared || folder.canAddLinks;
  }

  /// Personal folders plus shared boards the user may add to, for pickers.
  List<Folder> get addableFolders => [
        ...personalFolders,
        ...sharedFolders.where((f) => f.canAddLinks),
      ];

  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    settings.apply();
    if (settings.onboarded) await repo.seedIfNeeded();
    await repo.reclassifySources(); // the platform table may have grown since the link was saved
    await _countImpressions(force: true);
    await reload();
    _periodic = Timer.periodic(AppConfig.syncInterval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  /// Background upkeep that also runs when signed out: pick up shares, fill in previews, sync.
  Future<void> _tick() async {
    await _ingestShares();
    await reload();
    unawaited(_backfillPreviews());
    await syncNow();
  }

  /// Pull-to-refresh. Returns at once, so the pull spinner never blocks the list; the work
  /// runs in the background behind a thin bar at the top ([refreshing]):
  /// shares, the newest platform rules, links still missing a preview, then a sync.
  /// Every link's page is no longer re-fetched; use [refetchAllPreviews] for that.
  Future<void> refresh({String? folderId}) {
    if (!refreshing) unawaited(_refreshInBackground(folderId: folderId, hard: false));
    return Future<void>.value();
  }

  /// Looks every link up again (pictures, titles, authors). Slow with many links, so it is a
  /// separate action in Profile; it runs in the background like [refresh].
  Future<void> refetchAllPreviews() {
    if (!refreshing) unawaited(_refreshInBackground(hard: true));
    return Future<void>.value();
  }

  Future<void> _refreshInBackground({String? folderId, required bool hard}) async {
    refreshing = true;
    _notify();
    try {
      await _ingestShares();
      await Future.wait([
        _refreshRules(),
        syncNow(),
        _backfillPreviews(force: true, hard: hard, folderId: folderId),
      ]);
    } finally {
      refreshing = false;
      _notify();
    }
  }

  /// Fetches the platform and title rules from the server when it is reachable. Silent: the
  /// bundled or last-fetched rules keep working if the server is away.
  Future<void> _refreshRules() async {
    try {
      final fresh = jsonEncode(await api.rules());
      if (PlatformRules.adopt(fresh)) {
        await sessions.setRulesRaw(fresh);
        if (await repo.reclassifySources() > 0) {
          await reload();
          _scheduleSync();
        }
      }
    } catch (_) {
      // Offline, or the server has no rules endpoint yet.
    }
  }

  Future<void>? _backfillRun;

  /// When each link was last tried, so the background timer doesn't hammer unreachable ones.
  final Map<String, DateTime> _lastTried = {};
  static const _retryAfter = Duration(minutes: 5);

  /// Looks up every link that is not fetched yet (see [Item.fetched]). The user's own actions
  /// ([force]: pull to refresh, opening the app, saving) retry everything at once; the
  /// background timer waits a few minutes between tries of the same link.
  ///
  /// [hard] redoes links that are already fetched too ([folderId] limits that to one folder).
  Future<void> _backfillPreviews({bool force = false, bool hard = false, String? folderId}) {
    final running = _backfillRun;
    if (running != null && !hard) return running;
    Future<void> start() {
      late final Future<void> run;
      run = _runBackfill(force: force, hard: hard, folderId: folderId).whenComplete(() {
        if (identical(_backfillRun, run)) _backfillRun = null;
      });
      return _backfillRun = run;
    }

    // A hard refresh must not be swallowed by a background run already in flight.
    return running == null ? start() : running.then((_) => start());
  }

  Future<void> _runBackfill({required bool force, required bool hard, String? folderId}) async {
    final now = DateTime.now();
    final skip = <String>{
      if (!force)
        for (final e in _lastTried.entries)
          if (now.difference(e.value) < _retryAfter) e.key,
    };
    final before = {...skip};
    try {
      // The repository keeps several lookups in flight at once; the screen redraws at most
      // every couple of seconds instead of after every batch.
      var lastDraw = DateTime.now();
      var changed = false;
      while (await repo.backfillPreviews(skip, hard: hard, folderId: folderId, ignoreAttempts: force) > 0) {
        changed = true;
        if (DateTime.now().difference(lastDraw) > const Duration(seconds: 2)) {
          await reload();
          lastDraw = DateTime.now();
          changed = false;
        }
      }
      if (changed) await reload();
      _scheduleSync();
    } catch (_) {
      // Previews are a nicety; never let a lookup problem surface to the user.
    } finally {
      for (final id in skip.difference(before)) {
        _lastTried[id] = now;
      }
    }
  }

  /// App came back to the foreground (e.g. after sharing from Instagram).
  Future<void> onResumed() async {
    await _countImpressions();
    await reload();
    unawaited(_backfillPreviews(force: true)); // e.g. links saved in airplane mode
    // Shared links are saved (and their titles looked up) in the background, so the app
    // opens instantly; the list updates itself when they land.
    unawaited(_tick());
  }

  Future<void> reload() async {
    _folders = await db.folders();
    _items = await db.items();
    _members = await db.members();
    pendingChanges = await db.pendingCount();
    _notify();
  }

  Future<void> _ingestShares() async {
    final shares = await shareIntake.drain();
    var saved = 0;
    for (final share in shares) {
      if (share.choose) {
        _chooseQueue.add(share);
      } else {
        final shared = cleanedShareTitle(share.text, share.url);
        await repo.addLink(url: share.url, title: shared.title, author: shared.author);
        saved++;
      }
    }
    if (saved > 0) {
      _flashes.add(saved == 1 ? tr('Saved 1 link from another app') : tr('Saved {saved} links from other apps', {'saved': saved}));
      _scheduleSync();
      unawaited(_backfillPreviews(force: true));
    }
  }

  /// Each app open counts as one showing of the [New] items (resumes within 10 min don't).
  Future<void> _countImpressions({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastImpressions != null && now.difference(_lastImpressions!) < const Duration(minutes: 10)) {
      return;
    }
    _lastImpressions = now;
    final auto = await repo.registerImpressions();
    if (auto > 0) {
      _flashes.add(auto == 1 ? tr('1 save was filed automatically') : tr('{auto} saves were filed automatically', {'auto': auto}));
      _scheduleSync();
    }
  }

  /// Shares where the user tapped "Choose collection" in the Android dialog.
  PendingShare? takeChooseRequest() => _chooseQueue.isEmpty ? null : _chooseQueue.removeAt(0);
  bool get hasChooseRequest => _chooseQueue.isNotEmpty;

  /// One-shot messages for snackbars.
  String? takeFlash() => _flashes.isEmpty ? null : _flashes.removeAt(0);

  // ----------------------------------------------------------------- sync

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => syncNow());
  }

  Future<void> syncNow() async {
    if (!signedIn) {
      syncState = SyncState.localOnly;
      _notify();
      return;
    }
    syncState = SyncState.syncing;
    _notify();
    final result = await sync.run();
    switch (result.outcome) {
      case SyncOutcome.ok:
        syncState = SyncState.synced;
        lastSyncedAt = DateTime.now();
        syncMessage = result.rejected > 0 ? tr('{rejected} change(s) were not allowed and were undone', {'rejected': result.rejected}) : null;
      case SyncOutcome.offline:
        syncState = SyncState.offline;
        syncMessage = null;
      case SyncOutcome.sessionExpired:
        await _signOutLocally();
        _flashes.add(tr('Your session expired. Sign in again to keep syncing.'));
      case SyncOutcome.error:
        syncState = SyncState.error;
        syncMessage = result.message;
      case SyncOutcome.notSignedIn:
        syncState = SyncState.localOnly;
    }
    await reload();
  }

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final result = await action();
    await reload();
    _scheduleSync();
    return result;
  }

  // -------------------------------------------------------------- actions

  Future<Folder> createFolder({required String name, required int color, required String emoji, bool shared = false}) =>
      _mutate(() => repo.createFolder(name: name, color: color, emoji: emoji, isShared: shared));

  Future<Folder> autoFolderFor({required String url, String? title}) =>
      _mutate(() => repo.autoFolderFor(url: url, title: title));

  Future<void> updateFolder(Folder f, {String? name, int? color, String? emoji}) =>
      _mutate(() => repo.updateFolder(f, name: name, color: color, emoji: emoji));

  Future<void> deleteFolder(Folder f, {bool keepLinks = false}) =>
      _mutate(() => repo.deleteFolder(f, keepLinks: keepLinks));

  Future<Item> addLink({
    required String url,
    String? title,
    String? folderId,
    String? author,
    PagePreview? preview,
  }) async {
    final item = await _mutate(
        () => repo.addLink(url: url, title: title, folderId: folderId, author: author, preview: preview));
    unawaited(_backfillPreviews(force: true));
    return item;
  }

  Future<void> confirmItem(Item item, {String? moveTo}) => _mutate(() => repo.confirmItem(item, moveTo: moveTo));

  Future<void> moveItems(List<Item> items, String folderId) => _mutate(() => repo.moveItems(items, folderId));

  Future<RetryResult> retryUncategorized() => _mutate(repo.retryUncategorized);

  Future<void> deleteItems(List<Item> items) => _mutate(() => repo.deleteItems(items));

  Future<void> setFolderOrder(List<String> idsInOrder) => _mutate(() => repo.setFolderOrder(idsInOrder));

  Future<void> setItemOrder(List<String> idsInOrder) => _mutate(() => repo.setItemOrder(idsInOrder));

  /// Every link in a personal folder or Uncategorized, for regrouping.
  List<Item> get personalItems {
    final shared = sharedFolders.map((f) => f.id).toSet();
    return _items.where((i) => i.folderId == null || !shared.contains(i.folderId)).toList();
  }

  Future<int> applyRefactor(RefactorPlan plan) => _mutate(() => repo.applyRefactor(plan));

  /// The last refactor, while it can still be undone (24 hours).
  RefactorUndo? get refactorUndo => repo.refactorUndo;

  Future<int> undoRefactor() => _mutate(repo.undoRefactor);

  Future<void> moveItem(Item item, String folderId) => _mutate(() => repo.moveItem(item, folderId));

  Future<void> setTag(Item item, String? tag) => _mutate(() => repo.setTag(item, tag));

  Future<void> setTags(List<Item> items, String? tag) => _mutate(() => repo.setTags(items, tag));

  Future<void> deleteItem(Item item) => _mutate(() => repo.deleteItem(item));

  /// Edits a link's title and address. A new address is looked up again in the background.
  Future<Item> updateLink(Item item, {required String title, required String url}) async {
    final updated = await _mutate(() => repo.updateLink(item, title: title, url: url));
    unawaited(_backfillPreviews(force: true));
    return updated;
  }

  Future<void> setPinned(Item item, bool pinned) => _mutate(() => repo.setPinned(item, pinned));

  /// Undo a pin toggle, restoring who pinned it.
  Future<void> restorePin(Item previous) async {
    final current = itemById(previous.id);
    if (current == null) return;
    await _mutate(() => repo.restorePin(current, previous));
  }

  /// Invites need the board to exist on the server, so this syncs first and
  /// requires a connection. Returns 'added' or 'pending'.
  Future<String> invite(Folder board, String email, String role) async {
    final pre = await sync.run();
    if (pre.outcome == SyncOutcome.offline) throw const ApiUnreachable();
    final res = await api.invite(board.id, email.trim(), role);
    unawaited(syncNow());
    return (res['status'] as String?) ?? 'pending';
  }

  /// What the server offers for sign-in. Needs a connection.
  Future<AuthOptions> signInOptions() => auth.options();

  /// Sign-in moves this device's saves to the cloud and unlocks shared boards.
  Future<void> signInWithGoogle(AuthOptions options) async {
    await auth.signInWithGoogle(options);
    await _afterSignIn();
  }

  /// Development servers only (ALLOW_DEV_AUTH=true): any email works.
  Future<void> signInDev({required String provider, required String email, required String displayName}) async {
    await auth.signInDev(provider: provider, email: email, displayName: displayName);
    await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    await repo.enqueueFullUpload();
    await reload();
    await syncNow();
  }

  /// Deletes the account on the server (Play Store requirement). Like signing out, personal
  /// saves stay on this phone and shared boards leave it.
  Future<void> deleteAccount() async {
    await auth.deleteAccount();
    await _signOutLocally();
    await reload();
  }

  /// Personal saves stay on the device; shared boards and the sync queue are cleared.
  Future<void> signOut() async {
    await _signOutLocally();
    await reload();
  }

  Future<void> _signOutLocally() async {
    await db.resetForSignOut();
    await auth.signOut();
    syncState = SyncState.localOnly;
    syncMessage = null;
    lastSyncedAt = null;
  }

  // ----------------------------------------------------------- settings

  bool get needsOnboarding => !settings.onboarded;
  Region get region => settings.region;
  AppLanguage get language => L10n.current;

  /// First run: region, language and sources, then the demo collections (in that language).
  Future<void> completeOnboarding({
    required Region region,
    required AppLanguage language,
    required Set<String> sources,
  }) async {
    await settings.setRegion(region.code);
    await settings.setLanguage(language);
    await settings.setEnabledSources(sources);
    settings.apply();
    await repo.seedIfNeeded();
    await reload();
  }

  Future<void> setLanguage(AppLanguage language) async {
    await settings.setLanguage(language);
    settings.apply();
    _notify();
  }

  /// Changes the region; [resetSources] switches on that region's usual sources.
  Future<void> setRegion(Region region, {bool resetSources = false}) async {
    await settings.setRegion(region.code);
    if (resetSources) await settings.setEnabledSources(region.sources.toSet());
    settings.apply();
    _notify();
  }

  Future<void> setSourceEnabled(String key, bool on) async {
    final enabled = {...(settings.enabledSources ?? SourceCatalog.current.builtIns.map((s) => s.key).toSet())};
    on ? enabled.add(key) : enabled.remove(key);
    await settings.setEnabledSources(enabled);
    settings.apply();
    _notify();
  }

  /// Adds a source the app doesn't know (a news site, a local shop). Throws [StateError]
  /// with a message to show when the name or link isn't usable.
  Future<CustomSource> addCustomSource({required String name, required String exampleUrl}) async {
    final error = SourceCatalog.current.validate(name, exampleUrl);
    if (error != null) throw StateError(error);
    final source = CustomSource(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim(),
      host: CustomSource.hostOf(exampleUrl)!,
      exampleUrl: exampleUrl.trim(),
    );
    await settings.setCustomSources([...settings.customSources, source]);
    settings.apply();
    _notify();
    return source;
  }

  Future<void> removeCustomSource(CustomSource source) async {
    await settings.setCustomSources([for (final c in settings.customSources) if (c.id != source.id) c]);
    settings.apply();
    _notify();
  }

  /// Undo for a quick confirm: puts the link back exactly as it was.
  Future<void> restoreItem(Item previous) => _mutate(() => repo.restoreItem(previous));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
