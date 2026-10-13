/// What a refactor changed, kept for 24 hours so it can be taken back.
library;

/// A link as it was before the refactor moved it.
class ItemBefore {
  const ItemBefore({required this.id, required this.folderId, required this.status, required this.tag});

  final String id;

  /// null = it was in Uncategorized.
  final String? folderId;
  final String status;
  final String? tag;

  Map<String, Object?> toJson() => {'id': id, 'folder_id': folderId, 'status': status, 'tag': tag};

  factory ItemBefore.fromJson(Map<String, dynamic> j) => ItemBefore(
        id: j['id'] as String,
        folderId: j['folder_id'] as String?,
        status: (j['status'] as String?) ?? 'confirmed',
        tag: j['tag'] as String?,
      );
}

class RefactorUndo {
  const RefactorUndo({
    required this.at,
    required this.items,
    required this.createdFolderIds,
    required this.removedFolderIds,
  });

  /// How long a refactor can be undone.
  static const window = Duration(hours: 24);

  final DateTime at;
  final List<ItemBefore> items;

  /// Folders the refactor created: undo removes them.
  final List<String> createdFolderIds;

  /// Old folders the refactor emptied and removed: undo brings them back.
  final List<String> removedFolderIds;

  int get linkCount => items.length;

  bool isExpired([DateTime? now]) => (now ?? DateTime.now()).difference(at) > window;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'created': createdFolderIds,
        'removed': removedFolderIds,
      };

  factory RefactorUndo.fromJson(Map<String, dynamic> j) => RefactorUndo(
        at: DateTime.parse(j['at'] as String),
        items: [for (final i in (j['items'] as List)) ItemBefore.fromJson((i as Map).cast<String, dynamic>())],
        createdFolderIds: [for (final id in (j['created'] as List)) id as String],
        removedFolderIds: [for (final id in (j['removed'] as List)) id as String],
      );
}
