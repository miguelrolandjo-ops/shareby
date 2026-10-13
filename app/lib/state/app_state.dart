import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import '../data/refactor_planner.dart';
import '../data/repository.dart';
import '../data/session_store.dart';
import '../data/share_intake.dart';
import '../data/sync_service.dart';
import '../data/url_utils.dart';

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
  });

  final LocalDb db;
  final Repository repo;
  final SyncService sync;
  final AuthService auth;
  final SessionStore sessions;
  final ApiClient api;
  final ShareIntake shareIntake;

  List<Folder> _folders = const [];
  List<Item> _items = const [];
  List<Member> _members = const [];

  SyncState syncState = SyncState.localOnly;
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

  /// Items in a folder, including [New] items suggested into it.
  List<Item> itemsIn(String folderId) => folderId == kUncategorizedId
      ? _items.where((i) => i.folderId == null).toList()
      : _items.where((i) => i.folderId == folderId).toList();

  List<Member> membersOf(String folderId) => _members.where((m) => m.folderId == folderId).toList();

  Item? itemById(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Confirmed links in personal folders, or on boards where you can add pins.
  bool canMarkDone(Item item) {
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
    await repo.seedIfNeeded();
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

  /// Pull-to-refresh: everything above, and waits for it so the spinner means something.
  Future<void> refresh() async {
    await _ingestShares();
    await reload();
    await _backfillPreviews();
    await syncNow();
  }

  bool _backfilling = false;
  final Set<String> _previewTried = {};

  /// Instagram, TikTok and other links get their thumbnail (and real title) looked up on-device.
  Future<void> _backfillPreviews() async {
    if (_backfilling) return;
    _backfilling = true;
    try {
      while (await repo.backfillPreviews(_previewTried) > 0) {
        await reload();
        _scheduleSync();
      }
    } catch (_) {
      // Previews are a nicety; never let a lookup problem surface to the user.
    } finally {
      _backfilling = false;
    }
  }

  /// App came back to the foreground (e.g. after sharing from Instagram).
  Future<void> onResumed() async {
    await _countImpressions();
    await reload();
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
        await repo.addLink(url: share.url, title: titleFromShareText(share.text, share.url));
        saved++;
      }
    }
    if (saved > 0) {
      _flashes.add(saved == 1 ? 'Saved 1 link from another app' : 'Saved $saved links from other apps');
      _scheduleSync();
      unawaited(_backfillPreviews());
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
      _flashes.add(auto == 1 ? '1 save was filed automatically' : '$auto saves were filed automatically');
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
        syncMessage = result.rejected > 0 ? '${result.rejected} change(s) were not allowed and were undone' : null;
      case SyncOutcome.offline:
        syncState = SyncState.offline;
        syncMessage = null;
      case SyncOutcome.sessionExpired:
        await _signOutLocally();
        _flashes.add('Your session expired. Sign in again to keep syncing.');
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

  Future<Item> addLink({required String url, String? title, String? folderId}) async {
    final item = await _mutate(() => repo.addLink(url: url, title: title, folderId: folderId));
    unawaited(_backfillPreviews());
    return item;
  }

  Future<void> confirmItem(Item item, {String? moveTo}) => _mutate(() => repo.confirmItem(item, moveTo: moveTo));

  Future<void> moveItems(List<Item> items, String folderId) => _mutate(() => repo.moveItems(items, folderId));

  Future<RetryResult> retryUncategorized() => _mutate(repo.retryUncategorized);

  Future<void> deleteItems(List<Item> items) => _mutate(() => repo.deleteItems(items));

  Future<void> setItemOrder(List<String> idsInOrder) => _mutate(() => repo.setItemOrder(idsInOrder));

  /// Every link in a personal folder or Uncategorized, for regrouping.
  List<Item> get personalItems {
    final shared = sharedFolders.map((f) => f.id).toSet();
    return _items.where((i) => i.folderId == null || !shared.contains(i.folderId)).toList();
  }

  Future<int> applyRefactor(RefactorPlan plan) => _mutate(() => repo.applyRefactor(plan));

  Future<void> moveItem(Item item, String folderId) => _mutate(() => repo.moveItem(item, folderId));

  Future<void> setTag(Item item, String? tag) => _mutate(() => repo.setTag(item, tag));

  Future<void> deleteItem(Item item) => _mutate(() => repo.deleteItem(item));

  Future<void> setDone(Item item, bool done) => _mutate(() => repo.setDone(item, done));

  /// Undo a done toggle, restoring who ticked it.
  Future<void> restoreCompletion(Item previous) async {
    final current = itemById(previous.id);
    if (current == null) return;
    await _mutate(() => repo.restoreCompletion(current, previous));
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

  /// Sign-in moves this device's saves to the cloud and unlocks shared boards.
  Future<void> signIn({required String provider, required String email, required String displayName}) async {
    await auth.signIn(provider: provider, email: email, displayName: displayName);
    await repo.enqueueFullUpload();
    await reload();
    await syncNow();
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
