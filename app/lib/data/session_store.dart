import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Small key-value state: the signed-in session, the pull cursor and first-run flags.
///
/// The session token lives in the platform keystore (Android Keystore / iOS Keychain) via
/// flutter_secure_storage; only the non-secret profile (id, email, name) is in
/// shared_preferences. Everything is read once at start-up so lookups stay synchronous.
class SessionStore {
  SessionStore._(this._prefs, this._secure);

  /// Loads the saved session. Older installs kept the token in shared_preferences; it is
  /// moved to secure storage the first time this runs.
  static Future<SessionStore> open(SharedPreferences prefs, {FlutterSecureStorage? secure}) async {
    final store = SessionStore._(prefs, secure ?? const FlutterSecureStorage());
    await store._load();
    return store;
  }

  static const _sessionKey = 'session_v1';
  static const _tokenKey = 'session_token_v1';
  static const _cursorKey = 'pull_cursor_v1';
  static const _seededKey = 'seeded_v1';
  static const _refactorUndoKey = 'refactor_undo_v1';
  static const _rulesKey = 'platform_rules_v1';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  UserSession? _current;

  Future<void> _load() async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      var token = await _readToken();
      final legacy = json['token'];
      if (token == null && legacy is String && legacy.isNotEmpty) {
        token = legacy; // pre-secure-storage install: migrate
        await _secure.write(key: _tokenKey, value: token);
      }
      if (token == null) {
        await _prefs.remove(_sessionKey); // profile without a token: signed out
        return;
      }
      _current = UserSession.fromJson({...json, 'token': token});
      if (legacy != null) await _prefs.setString(_sessionKey, jsonEncode(_withoutToken(_current!)));
    } catch (_) {
      await _prefs.remove(_sessionKey);
    }
  }

  Future<String?> _readToken() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (_) {
      // Keystore entry unreadable (e.g. restored from a backup on another phone): sign in again.
      await _secure.delete(key: _tokenKey);
      return null;
    }
  }

  static Map<String, Object?> _withoutToken(UserSession s) => {...s.toJson()}..remove('token');

  UserSession? get current => _current;
  bool get isSignedIn => _current != null;

  Future<void> save(UserSession session) async {
    _current = session;
    await _secure.write(key: _tokenKey, value: session.token);
    await _prefs.setString(_sessionKey, jsonEncode(_withoutToken(session)));
  }

  Future<void> clear() async {
    _current = null;
    await _prefs.remove(_sessionKey);
    await _prefs.remove(_cursorKey);
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {
      // Nothing stored.
    }
  }

  String? get pullCursor => _prefs.getString(_cursorKey);

  Future<void> setPullCursor(String? cursor) async {
    if (cursor == null) {
      await _prefs.remove(_cursorKey);
    } else {
      await _prefs.setString(_cursorKey, cursor);
    }
  }

  /// The last refactor's undo snapshot (JSON), kept for 24 hours. See [RefactorUndo].
  String? get refactorUndoRaw => _prefs.getString(_refactorUndoKey);

  Future<void> setRefactorUndoRaw(String? raw) async {
    if (raw == null) {
      await _prefs.remove(_refactorUndoKey);
    } else {
      await _prefs.setString(_refactorUndoKey, raw);
    }
  }

  /// The newest platform rules fetched from the server (JSON), used until a newer set arrives.
  String? get rulesRaw => _prefs.getString(_rulesKey);

  Future<void> setRulesRaw(String raw) async => _prefs.setString(_rulesKey, raw);

  bool get seeded => _prefs.getBool(_seededKey) ?? false;
  Future<void> markSeeded() async => _prefs.setBool(_seededKey, true);
}
