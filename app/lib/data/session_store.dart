import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Small key-value state: the signed-in session, the pull cursor and first-run flags.
/// Production note: move the token to flutter_secure_storage (Keychain / Keystore).
class SessionStore {
  SessionStore(this._prefs) {
    final raw = _prefs.getString(_sessionKey);
    if (raw != null) {
      try {
        _current = UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _prefs.remove(_sessionKey);
      }
    }
  }

  static const _sessionKey = 'session_v1';
  static const _cursorKey = 'pull_cursor_v1';
  static const _seededKey = 'seeded_v1';
  static const _refactorUndoKey = 'refactor_undo_v1';
  static const _rulesKey = 'platform_rules_v1';

  final SharedPreferences _prefs;
  UserSession? _current;

  UserSession? get current => _current;
  bool get isSignedIn => _current != null;

  Future<void> save(UserSession session) async {
    _current = session;
    await _prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    _current = null;
    await _prefs.remove(_sessionKey);
    await _prefs.remove(_cursorKey);
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
