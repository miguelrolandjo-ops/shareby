import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// A change waiting to be pushed to the server.
class OutboxOp {
  const OutboxOp({required this.opId, required this.entity, required this.entityId, required this.payload});

  final String opId;

  /// 'folder' | 'item'
  final String entity;
  final String entityId;
  final Map<String, Object?> payload;

  Map<String, Object?> toApi() => {'op_id': opId, 'entity': entity, 'data': payload};
}

/// On-device SQLite database — the app's source of truth, online or not.
///
/// Every local edit writes the row and (when signed in) an outbox entry in one
/// transaction. The outbox keeps at most one entry per record holding its latest
/// full state, so ten offline edits to a folder become one push.
/// `dirty = 1` marks rows with unpushed edits; pulls never overwrite those.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open({String name = 'shareby.db'}) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), name),
      version: 6,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return LocalDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE folders (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color INTEGER NOT NULL,
          emoji TEXT NOT NULL,
          is_shared INTEGER NOT NULL DEFAULT 0,
          owner_id TEXT,
          my_role TEXT NOT NULL DEFAULT 'owner',
          sort_order INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0,
          dirty INTEGER NOT NULL DEFAULT 0
        )''')
      ..execute('''
        CREATE TABLE items (
          id TEXT PRIMARY KEY,
          folder_id TEXT,
          url TEXT NOT NULL,
          title TEXT NOT NULL,
          source TEXT NOT NULL,
          author TEXT,
          thumbnail_url TEXT,
          thumb_path TEXT,
          fetch_attempts INTEGER NOT NULL DEFAULT 0,
          tag TEXT,
          status TEXT NOT NULL,
          suggested_folder_id TEXT,
          confidence REAL NOT NULL DEFAULT 0,
          view_count INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER,
          fetched INTEGER NOT NULL DEFAULT 0,
          added_by TEXT,
          added_by_name TEXT,
          completed_at TEXT,
          completed_by TEXT,
          completed_by_name TEXT,
          completion_updated_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0,
          dirty INTEGER NOT NULL DEFAULT 0
        )''')
      ..execute('CREATE INDEX items_folder_idx ON items (folder_id)')
      ..execute('''
        CREATE TABLE members (
          folder_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          display_name TEXT NOT NULL,
          role TEXT NOT NULL,
          PRIMARY KEY (folder_id, user_id)
        )''')
      ..execute('''
        CREATE TABLE outbox (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          op_id TEXT NOT NULL,
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL
        )''')
      ..execute('CREATE INDEX outbox_entity_idx ON outbox (entity, entity_id)');
    await batch.commit(noResult: true);
  }

  /// Schema migrations for installs created by an older version of the app.
  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: "done" checkmark
      final batch = db.batch()
        ..execute('ALTER TABLE items ADD COLUMN completed_at TEXT')
        ..execute('ALTER TABLE items ADD COLUMN completed_by TEXT')
        ..execute('ALTER TABLE items ADD COLUMN completed_by_name TEXT')
        ..execute('ALTER TABLE items ADD COLUMN completion_updated_at TEXT');
      await batch.commit(noResult: true);
    }
    if (oldVersion < 6) {
      // v6: who made the post (synced), the thumbnail file kept on this device, and how many
      // lookups failed (both device-local).
      final batch = db.batch()
        ..execute('ALTER TABLE items ADD COLUMN author TEXT')
        ..execute('ALTER TABLE items ADD COLUMN thumb_path TEXT')
        ..execute('ALTER TABLE items ADD COLUMN fetch_attempts INTEGER NOT NULL DEFAULT 0');
      await batch.commit(noResult: true);
    }
    if (oldVersion < 5) {
      // v5: `fetched` = the link's page was looked up. Links that already have a thumbnail
      // answer and a real title count as fetched; the rest will be retried on refresh.
      final batch = db.batch()
        ..execute('ALTER TABLE items ADD COLUMN fetched INTEGER NOT NULL DEFAULT 0')
        ..execute("UPDATE items SET fetched = 1 WHERE thumbnail_url IS NOT NULL AND title NOT LIKE 'Saved from %'");
      await batch.commit(noResult: true);
    }
    if (oldVersion < 4) {
      // v4: manual folder order on Home (device-local)
      await db.execute('ALTER TABLE folders ADD COLUMN sort_order INTEGER');
    }
    if (oldVersion < 3) {
      // v3: manual ordering inside a folder (device-local)
      await db.execute('ALTER TABLE items ADD COLUMN sort_order INTEGER');
    }
  }

  // ---------------------------------------------------------------- reads

  Future<List<Folder>> folders() async {
    final rows =
        await _db.query('folders', where: 'deleted = 0', orderBy: 'COALESCE(sort_order, 1000000) ASC, created_at ASC');
    return rows.map(Folder.fromDb).toList();
  }

  Future<List<Item>> items() async {
    final rows = await _db.query('items', where: 'deleted = 0', orderBy: 'sort_order ASC, created_at DESC');
    return rows.map(Item.fromDb).toList();
  }

  Future<Item?> itemById(String id) async {
    final rows = await _db.query('items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Item.fromDb(rows.first);
  }

  Future<Folder?> folderById(String id) async {
    final rows = await _db.query('folders', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Folder.fromDb(rows.first);
  }

  Future<List<Member>> members() async {
    final rows = await _db.query('members', orderBy: 'display_name ASC');
    return rows.map(Member.fromDb).toList();
  }

  Future<bool> isEmpty() async {
    final count = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM folders'));
    return (count ?? 0) == 0;
  }

  // --------------------------------------------------------------- writes

  /// Saves a folder. Pass [enqueueOpId] (only when signed in) to queue it for sync.
  Future<void> saveFolder(Folder f, {String? enqueueOpId}) async {
    await _db.transaction((txn) async {
      await txn.insert('folders', f.toDb(dirty: enqueueOpId != null), conflictAlgorithm: ConflictAlgorithm.replace);
      if (enqueueOpId != null) await _enqueue(txn, enqueueOpId, 'folder', f.id, f.toApi());
    });
  }

  Future<void> saveItem(Item i, {String? enqueueOpId}) async {
    await _db.transaction((txn) async {
      await txn.insert('items', i.toDb(dirty: enqueueOpId != null), conflictAlgorithm: ConflictAlgorithm.replace);
      if (enqueueOpId != null) await _enqueue(txn, enqueueOpId, 'item', i.id, i.toApi());
    });
  }

  /// Changes only device-local columns (thumb_path, fetch_attempts, fetched): no outbox
  /// entry, no new updated_at, so it never shows up as an edit to sync.
  Future<void> updateLocal(String itemId, Map<String, Object?> values) async {
    await _db.update('items', values, where: 'id = ?', whereArgs: [itemId]);
  }

  /// Device-local counter for the auto-confirm rule; intentionally not synced.
  Future<void> setViewCount(String itemId, int count) async {
    await _db.update('items', {'view_count': count}, where: 'id = ?', whereArgs: [itemId]);
  }

  /// Manual order of folders on Home: ids in display order. Device-local, never synced.
  Future<void> setFolderSortOrders(List<String> idsInOrder) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await txn.update('folders', {'sort_order': i}, where: 'id = ?', whereArgs: [idsInOrder[i]]);
      }
    });
  }

  /// Manual order inside a folder: ids in display order. Device-local, never synced.
  Future<void> setSortOrders(List<String> idsInOrder) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await txn.update('items', {'sort_order': i}, where: 'id = ?', whereArgs: [idsInOrder[i]]);
      }
    });
  }

  static Future<void> _enqueue(
    DatabaseExecutor txn,
    String opId,
    String entity,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    await txn.delete('outbox', where: 'entity = ? AND entity_id = ?', whereArgs: [entity, entityId]);
    await txn.insert('outbox', {
      'op_id': opId,
      'entity': entity,
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // --------------------------------------------------------------- outbox

  /// Folders first, so a new folder exists on the server before items that reference it.
  Future<List<OutboxOp>> pendingOps({int limit = 50}) async {
    final rows = await _db.rawQuery(
      "SELECT * FROM outbox ORDER BY CASE entity WHEN 'folder' THEN 0 ELSE 1 END, seq LIMIT ?",
      [limit],
    );
    return rows
        .map((r) => OutboxOp(
              opId: r['op_id'] as String,
              entity: r['entity'] as String,
              entityId: r['entity_id'] as String,
              payload: (jsonDecode(r['payload'] as String) as Map).cast<String, Object?>(),
            ))
        .toList();
  }

  Future<int> pendingCount() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  /// Removes pushed ops and clears `dirty` — unless the record was edited again
  /// while the push was in flight (then a newer op is still queued).
  Future<void> completeOps(List<OutboxOp> ops) async {
    if (ops.isEmpty) return;
    await _db.transaction((txn) async {
      for (final op in ops) {
        await txn.delete('outbox', where: 'op_id = ?', whereArgs: [op.opId]);
        final table = op.entity == 'folder' ? 'folders' : 'items';
        await txn.rawUpdate(
          'UPDATE $table SET dirty = 0 WHERE id = ? '
          'AND NOT EXISTS (SELECT 1 FROM outbox WHERE entity_id = ?)',
          [op.entityId, op.entityId],
        );
      }
    });
  }

  // ------------------------------------------------------- server changes

  /// Applies one /sync/pull response atomically.
  Future<void> applyServerChanges({
    required List<Folder> folders,
    required List<Item> items,
    required List<Member> members,
    required Set<String> accessibleFolderIds,
    bool full = false,
  }) async {
    await _db.transaction((txn) async {
      Future<bool> dirty(String table, String id) async {
        final rows = await txn.query(table, columns: ['dirty'], where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isNotEmpty && rows.first['dirty'] == 1;
      }

      for (final f in folders) {
        if (await dirty('folders', f.id)) continue; // our unpushed edit wins; it syncs next
        final order = await txn.query('folders', columns: ['sort_order'], where: 'id = ?', whereArgs: [f.id], limit: 1);
        final keep = order.isEmpty ? null : order.first['sort_order'] as int?;
        await txn.insert('folders', f.copyWith(sortOrder: keep).toDb(dirty: false),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final i in items) {
        final existing = await txn.query('items',
            columns: ['dirty', 'view_count', 'sort_order', 'fetched', 'thumbnail_url', 'thumb_path', 'fetch_attempts'],
            where: 'id = ?',
            whereArgs: [i.id],
            limit: 1);
        if (existing.isNotEmpty && existing.first['dirty'] == 1) continue;
        final row = existing.isEmpty ? null : existing.first;
        final views = row == null ? 0 : (row['view_count'] as int? ?? 0);
        final order = row?['sort_order'] as int?;
        // Looked up on this device, or the server already filled in the thumbnail.
        final fetched = (row != null && row['fetched'] == 1) || i.thumbnailUrl != null;
        // The picture saved on this device stays, unless another device changed the link's image.
        final sameImage = row != null && row['thumbnail_url'] == i.thumbnailUrl;
        final thumb = sameImage ? row['thumb_path'] as String? : null;
        await txn.insert(
            'items',
            i
                .copyWith(
                  viewCount: views,
                  sortOrder: order,
                  fetched: fetched,
                  thumbPath: thumb,
                  fetchAttempts: sameImage ? (row['fetch_attempts'] as int? ?? 0) : 0,
                )
                .toDb(dirty: false),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // A full resync lists everything this account has: synced records missing from it were
      // deleted elsewhere long ago. Unpushed local edits (dirty) always stay.
      if (full) {
        final keepItems = items.map((i) => i.id).toSet();
        final keepFolders = folders.map((f) => f.id).toSet();
        for (final row in await txn.query('items', columns: ['id'], where: 'dirty = 0')) {
          final id = row['id'] as String;
          if (!keepItems.contains(id)) await txn.delete('items', where: 'id = ?', whereArgs: [id]);
        }
        for (final row in await txn.query('folders', columns: ['id'], where: 'dirty = 0')) {
          final id = row['id'] as String;
          if (!keepFolders.contains(id)) await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
        }
      }

      // Boards we were removed from (or that were deleted) disappear from this device.
      final shared = await txn.query('folders', columns: ['id'], where: 'is_shared = 1 AND dirty = 0');
      for (final row in shared) {
        final id = row['id'] as String;
        if (!accessibleFolderIds.contains(id)) await _deleteSharedFolder(txn, id);
      }

      await txn.delete('members');
      for (final m in members) {
        await txn.insert('members', m.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<void> _deleteSharedFolder(DatabaseExecutor txn, String folderId) async {
    await txn.delete('items', where: 'folder_id = ?', whereArgs: [folderId]);
    await txn.delete('members', where: 'folder_id = ?', whereArgs: [folderId]);
    await txn.delete('folders', where: 'id = ?', whereArgs: [folderId]);
  }

  /// Signing out: shared boards leave the device, personal saves stay (offline-first).
  Future<void> resetForSignOut() async {
    await _db.transaction((txn) async {
      final shared = await txn.query('folders', columns: ['id'], where: 'is_shared = 1');
      for (final row in shared) {
        await _deleteSharedFolder(txn, row['id'] as String);
      }
      await txn.delete('outbox');
      await txn.update('folders', {'dirty': 0});
      await txn.update('items', {'dirty': 0});
    });
  }
}
