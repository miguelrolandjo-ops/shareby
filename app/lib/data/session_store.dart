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

  bool get seeded => _prefs.getBool(_seededKey) ?? false;
  Future<void> markSeeded() async => _prefs.setBool(_seededKey, true);
}
