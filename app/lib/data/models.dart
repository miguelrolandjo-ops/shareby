/// Plain data classes shared by the local database, the sync layer and the UI.
/// Each knows how to map itself to a SQLite row (`toDb`/`fromDb`) and to the
/// API's JSON (`toApi`/`fromApi`).
library;

import 'url_utils.dart';

/// Pseudo-folder for personal saves that have no collection.
const kUncategorizedId = '__uncategorized__';

String _iso(DateTime d) => d.toUtc().toIso8601String();
DateTime _parse(Object? v) => DateTime.parse(v as String).toUtc();
String? _isoOrNull(DateTime? d) => d == null ? null : _iso(d);
DateTime? _parseOrNull(Object? v) => v is String && v.isNotEmpty ? DateTime.parse(v).toUtc() : null;

class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.color,
    required this.emoji,
    required this.isShared,
    required this.createdAt,
    required this.updatedAt,
    this.ownerId,
    this.myRole = 'owner',
    this.sortOrder,
    this.deleted = false,
  });

  final String id;
  final String name;
  final int color; // ARGB
  final String emoji;

  /// Shared boards live under Friends; personal folders live on Home.
  final bool isShared;
  final String? ownerId;

  /// owner | editor | viewer — only meaningful for shared boards.
  final String myRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Position on Home (lower = earlier). Device-local, never synced; null = never moved,
  /// so it goes after the ones that were.
  final int? sortOrder;
  final bool deleted;

  bool get isUncategorized => id == kUncategorizedId;
  bool get isOwner => myRole == 'owner';
  bool get canAddLinks => !isUncategorized && (myRole == 'owner' || myRole == 'editor');

  static Folder uncategorized() => Folder(
        id: kUncategorizedId,
        name: 'Uncategorized',
        color: 0xFF9AA39D,
        emoji: '🗂️',
        isShared: false,
        createdAt: DateTime.utc(2020),
        updatedAt: DateTime.utc(2020),
      );

  Folder copyWith({
    String? name,
    int? color,
    String? emoji,
    String? ownerId,
    String? myRole,
    int? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      Folder(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        emoji: emoji ?? this.emoji,
        isShared: isShared,
        ownerId: ownerId ?? this.ownerId,
        myRole: myRole ?? this.myRole,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object?> toDb({required bool dirty}) => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
        'color': color,
        'emoji': emoji,
        'is_shared': isShared ? 1 : 0,
        'owner_id': ownerId,
        'my_role': myRole,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory Folder.fromDb(Map<String, Object?> m) => Folder(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        emoji: m['emoji'] as String,
        isShared: m['is_shared'] == 1,
        ownerId: m['owner_id'] as String?,
        myRole: (m['my_role'] as String?) ?? 'owner',
        sortOrder: m['sort_order'] as int?,
        createdAt: _parse(m['created_at']),
        updatedAt: _parse(m['updated_at']),
        deleted: m['deleted'] == 1,
      );

  Map<String, Object?> toApi() => {
        'id': id,
        'name': name,
        'color': color,
        'emoji': emoji,
        'is_shared': isShared,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': deleted ? _iso(updatedAt) : null,
      };

  factory Folder.fromApi(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String,
        color: (j['color'] as num).toInt(),
        emoji: (j['emoji'] as String?) ?? '📁',
        isShared: j['is_shared'] == true,
        ownerId: j['owner_id'] as String?,
        myRole: (j['my_role'] as String?) ?? 'owner',
        createdAt: _parse(j['created_at']),
        updatedAt: _parse(j['updated_at']),
        deleted: j['deleted_at'] != null,
      );
}

class Item {
  const Item({
    required this.id,
    required this.url,
    required this.title,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.thumbnailUrl,
    this.tag,
    this.suggestedFolderId,
    this.confidence = 0,
    this.viewCount = 0,
    this.addedBy,
    this.addedByName,
    this.completedAt,
    this.completedBy,
    this.completedByName,
    this.completionUpdatedAt,
    this.sortOrder,
    this.fetched = false,
    this.author,
    this.thumbPath,
    this.fetchAttempts = 0,
    this.deleted = false,
  });

  final String id;

  /// null = Uncategorized. For [New] items this is the suggested folder, so the
  /// item also shows up inside that folder before it is confirmed.
  final String? folderId;
  final String url;
  final String title;

  /// A platform key from the rules table (instagram, shopee...), or 'web'.
  final String source;

  /// Who made the post ("Mia" from "Mia on Instagram: ..."), when known. Synced with the title.
  final String? author;

  /// null = not looked up yet, '' = looked up and nothing found.
  final String? thumbnailUrl;

  /// Personal folders only.
  final String? tag;

  /// 'new' (auto-categorized, awaiting confirmation) or 'confirmed'.
  final String status;
  final String? suggestedFolderId;
  final double confidence;

  /// How many times this [New] item has been shown. Device-local, never synced.
  final int viewCount;
  final String? addedBy;
  final String? addedByName;

  /// "Pinned" (stored under the old "completed" names so existing data carries over): a pinned
  /// link sorts to the top of its folder. On shared boards a pin is shared by everyone;
  /// [completedBy] is who pinned it.
  final DateTime? completedAt;
  final String? completedBy;
  final String? completedByName;

  /// When pinned/unpinned last changed. Merged separately from content edits.
  final DateTime? completionUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Manual position inside a folder (lower = earlier). Device-local like [viewCount];
  /// null = never reordered, so it shows first, newest first.
  final int? sortOrder;

  /// true once the link's page was looked up successfully (real title and thumbnail, or
  /// confirmed to have none). false = not yet, e.g. saved offline: pull-to-refresh retries it.
  /// Device-local, never synced.
  final bool fetched;

  /// File name of the compressed thumbnail kept on this device (see ThumbnailStore), or null
  /// when there is none yet. Device-local, never synced.
  final String? thumbPath;

  /// Failed lookups so far; after a few the app stops retrying on its own. Device-local.
  final int fetchAttempts;
  final bool deleted;

  bool get isNew => status == 'new';
  bool get isPinned => completedAt != null;

  Item copyWith({
    String? folderId,
    bool clearFolder = false,
    String? title,
    String? url,
    String? source,
    String? author,
    bool clearAuthor = false,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
    String? thumbPath,
    bool clearThumbPath = false,
    int? fetchAttempts,
    String? tag,
    bool clearTag = false,
    String? status,
    int? viewCount,
    String? suggestedFolderId,
    double? confidence,
    int? sortOrder,
    bool? fetched,
    DateTime? updatedAt,
    bool? deleted,
    DateTime? completedAt,
    String? completedBy,
    String? completedByName,
    bool clearCompleted = false,
    DateTime? completionUpdatedAt,
  }) =>
      Item(
        id: id,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        url: url ?? this.url,
        title: title ?? this.title,
        source: source ?? this.source,
        author: clearAuthor ? null : (author ?? this.author),
        thumbnailUrl: clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
        thumbPath: clearThumbPath ? null : (thumbPath ?? this.thumbPath),
        fetchAttempts: fetchAttempts ?? this.fetchAttempts,
        tag: clearTag ? null : (tag ?? this.tag),
        status: status ?? this.status,
        suggestedFolderId: suggestedFolderId ?? this.suggestedFolderId,
        confidence: confidence ?? this.confidence,
        viewCount: viewCount ?? this.viewCount,
        addedBy: addedBy,
        addedByName: addedByName,
        completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
        completedBy: clearCompleted ? null : (completedBy ?? this.completedBy),
        completedByName: clearCompleted ? null : (completedByName ?? this.completedByName),
        completionUpdatedAt: completionUpdatedAt ?? this.completionUpdatedAt,
        sortOrder: sortOrder ?? this.sortOrder,
        fetched: fetched ?? this.fetched,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object?> toDb({required bool dirty}) => {
        'id': id,
        'folder_id': folderId,
        'url': url,
        'title': title,
        'source': source,
        'author': author,
        'thumbnail_url': thumbnailUrl,
        'thumb_path': thumbPath,
        'fetch_attempts': fetchAttempts,
        'tag': tag,
        'status': status,
        'suggested_folder_id': suggestedFolderId,
        'confidence': confidence,
        'view_count': viewCount,
        'sort_order': sortOrder,
        'fetched': fetched ? 1 : 0,
        'added_by': addedBy,
        'added_by_name': addedByName,
        'completed_at': _isoOrNull(completedAt),
        'completed_by': completedBy,
        'completed_by_name': completedByName,
        'completion_updated_at': _isoOrNull(completionUpdatedAt),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory Item.fromDb(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        folderId: m['folder_id'] as String?,
        url: m['url'] as String,
        title: decodeHtmlEntities(m['title'] as String),
        source: m['source'] as String,
        author: m['author'] as String?,
        thumbnailUrl: m['thumbnail_url'] as String?,
        thumbPath: m['thumb_path'] as String?,
        fetchAttempts: (m['fetch_attempts'] as int?) ?? 0,
        tag: m['tag'] as String?,
        status: m['status'] as String,
        suggestedFolderId: m['suggested_folder_id'] as String?,
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        viewCount: (m['view_count'] as int?) ?? 0,
        sortOrder: m['sort_order'] as int?,
        fetched: m['fetched'] == 1,
        addedBy: m['added_by'] as String?,
        addedByName: m['added_by_name'] as String?,
        completedAt: _parseOrNull(m['completed_at']),
        completedBy: m['completed_by'] as String?,
        completedByName: m['completed_by_name'] as String?,
        completionUpdatedAt: _parseOrNull(m['completion_updated_at']),
        createdAt: _parse(m['created_at']),
        updatedAt: _parse(m['updated_at']),
        deleted: m['deleted'] == 1,
      );

  /// view_count and added_by_name are deliberately not sent: the server derives
  /// the author from the session, and view counts stay on the device.
  Map<String, Object?> toApi() => {
        'id': id,
        'folder_id': folderId,
        'url': url,
        'title': title,
        'source': source,
        'author': author,
        'thumbnail_url': thumbnailUrl,
        'tag': tag,
        'status': status,
        'suggested_folder_id': suggestedFolderId,
        'confidence': confidence,
        'completed_at': _isoOrNull(completedAt),
        'completion_updated_at': _isoOrNull(completionUpdatedAt),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': deleted ? _iso(updatedAt) : null,
      };

  factory Item.fromApi(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        folderId: j['folder_id'] as String?,
        url: j['url'] as String,
        title: decodeHtmlEntities(j['title'] as String),
        source: (j['source'] as String?) ?? 'web',
        author: j['author'] as String?,
        thumbnailUrl: j['thumbnail_url'] as String?,
        tag: j['tag'] as String?,
        status: (j['status'] as String?) ?? 'confirmed',
        suggestedFolderId: j['suggested_folder_id'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        addedBy: j['added_by'] as String?,
        addedByName: j['added_by_name'] as String?,
        completedAt: _parseOrNull(j['completed_at']),
        completedBy: j['completed_by'] as String?,
        completedByName: j['completed_by_name'] as String?,
        completionUpdatedAt: _parseOrNull(j['completion_updated_at']),
        createdAt: _parse(j['created_at']),
        updatedAt: _parse(j['updated_at']),
        deleted: j['deleted_at'] != null,
      );
}

class Member {
  const Member({
    required this.folderId,
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String folderId;
  final String userId;
  final String displayName;
  final String role;

  Map<String, Object?> toDb() => {
        'folder_id': folderId,
        'user_id': userId,
        'display_name': displayName,
        'role': role,
      };

  factory Member.fromDb(Map<String, Object?> m) => Member(
        folderId: m['folder_id'] as String,
        userId: m['user_id'] as String,
        displayName: m['display_name'] as String,
        role: m['role'] as String,
      );

  factory Member.fromApi(Map<String, dynamic> j) => Member(
        folderId: j['folder_id'] as String,
        userId: j['user_id'] as String,
        displayName: (j['display_name'] as String?) ?? 'Friend',
        role: (j['role'] as String?) ?? 'editor',
      );
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.token,
  });

  final String userId;
  final String email;
  final String displayName;

  /// google | apple
  final String provider;
  final String token;

  Map<String, Object?> toJson() => {
        'user_id': userId,
        'email': email,
        'display_name': displayName,
        'provider': provider,
        'token': token,
      };

  factory UserSession.fromJson(Map<String, dynamic> j) => UserSession(
        userId: j['user_id'] as String,
        email: j['email'] as String,
        displayName: j['display_name'] as String,
        provider: j['provider'] as String,
        token: j['token'] as String,
      );

  /// Shape returned by POST /auth/*: { token, user: { id, email, display_name } }
  factory UserSession.fromLogin(Map<String, dynamic> body, String provider) {
    final user = body['user'] as Map<String, dynamic>;
    return UserSession(
      userId: user['id'] as String,
      email: user['email'] as String,
      displayName: user['display_name'] as String,
      provider: provider,
      token: body['token'] as String,
    );
  }
}

/// A link that arrived through the Android share sheet while the app was closed.
class PendingShare {
  const PendingShare({required this.url, this.text, this.choose = false});

  final String url;
  final String? text;

  /// true = the user tapped "Choose collection" and expects the picker when the app opens.
  final bool choose;
}
