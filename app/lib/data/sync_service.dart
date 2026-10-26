import 'api_client.dart';
import 'local_db.dart';
import 'models.dart';
import 'session_store.dart';

enum SyncOutcome { ok, offline, sessionExpired, error, notSignedIn }

class SyncResult {
  const SyncResult(this.outcome, {this.message, this.rejected = 0});
  final SyncOutcome outcome;
  final String? message;

  /// Ops the server refused (e.g. a viewer trying to add a pin). They are dropped and
  /// a full pull restores the server's version.
  final int rejected;
}

/// Moves changes between SQLite and the server: push the outbox, then pull.
/// Safe to call often and concurrently — overlapping calls are coalesced.
class SyncService {
  SyncService({required this.db, required this.api, required this.sessions});

  final LocalDb db;
  final ApiClient api;
  final SessionStore sessions;
  Future<SyncResult>? _inFlight;

  Future<SyncResult> run() {
    if (!sessions.isSignedIn) return Future.value(const SyncResult(SyncOutcome.notSignedIn));
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<SyncResult> _run() async {
    try {
      final rejected = await _push();
      // A refused change was already applied locally. Pull everything once so the
      // phone shows the server's version again (rare, so a full pull is fine).
      if (rejected > 0) await sessions.setPullCursor(null);
      await _pull();
      return SyncResult(SyncOutcome.ok, rejected: rejected);
    } on ApiUnreachable {
      return const SyncResult(SyncOutcome.offline);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return SyncResult(SyncOutcome.sessionExpired, message: e.message);
      return SyncResult(SyncOutcome.error, message: e.message);
    }
  }

  Future<int> _push() async {
    var rejectedCount = 0;
    for (var round = 0; round < 40; round++) {
      final ops = await db.pendingOps(limit: 50);
      if (ops.isEmpty) break;
      final res = await api.push(ops.map((o) => o.toApi()).toList());

      final done = <String>{
        ...((res['applied'] as List?) ?? const []).whereType<String>(),
      };
      for (final r in ((res['rejected'] as List?) ?? const []).whereType<Map>()) {
        final id = r['op_id'];
        if (id is String) {
          done.add(id);
          rejectedCount++;
        }
      }
      if (done.isEmpty) break; // server made no progress; try again next sync
      await db.completeOps(ops.where((o) => done.contains(o.opId)).toList());
    }
    return rejectedCount;
  }

  Future<void> _pull() async {
    final res = await api.pull(sessions.pullCursor);
    List<Map<String, dynamic>> list(String key) =>
        ((res[key] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();

    await db.applyServerChanges(
      folders: list('folders').map(Folder.fromApi).toList(),
      items: list('items').map(Item.fromApi).toList(),
      members: list('members').map(Member.fromApi).toList(),
      accessibleFolderIds: ((res['accessible_folder_ids'] as List?) ?? const []).whereType<String>().toSet(),
      // This phone was away longer than the server keeps deletes: it sent everything instead.
      full: res['full'] == true,
    );
    final cursor = res['cursor'];
    if (cursor is String) await sessions.setPullCursor(cursor);
  }
}
