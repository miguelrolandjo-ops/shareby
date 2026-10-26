import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';
import 'models.dart';
import 'session_store.dart';

/// What the server offers for signing in (GET /auth/config).
class AuthOptions {
  const AuthOptions({this.googleClientId, this.dev = false, this.apple = false});

  /// The Web OAuth client ID. On Android it is the `serverClientId`: Google issues the ID
  /// token for it, and the server checks the token against it.
  final String? googleClientId;

  /// The server accepts development sign-in (any email). Never on in production.
  final bool dev;
  final bool apple;

  bool get google => googleClientId != null;

  factory AuthOptions.fromJson(Map<String, dynamic> j) {
    final id = j['google_client_id'];
    return AuthOptions(
      googleClientId: id is String && id.isNotEmpty ? id : null,
      dev: j['dev'] == true,
      apple: j['apple'] == true,
    );
  }
}

/// The user closed Google's account picker. Not an error worth showing.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Signs the user in and stores the session.
///
///  * Google: the Android account picker (Credential Manager, via google_sign_in) returns an ID
///    token for the server's Web client ID; the server verifies it and returns a session.
///  * Development servers (ALLOW_DEV_AUTH=true) also accept any email, so two emulators can
///    play two friends.
///  * Apple: the server side is ready (POST /auth/apple); the iOS app adds sign_in_with_apple
///    in phase 2 and calls [ApiClient.appleLogin].
class AuthService {
  AuthService({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;
  String? _googleReadyFor;

  Future<AuthOptions> options() async => AuthOptions.fromJson(await api.authConfig());

  Future<UserSession> signInWithGoogle(AuthOptions options) async {
    final clientId = options.googleClientId;
    if (clientId == null) throw StateError('Google sign-in is not set up on the server yet.');
    final google = GoogleSignIn.instance;
    if (_googleReadyFor != clientId) {
      await google.initialize(serverClientId: clientId);
      _googleReadyFor = clientId;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted ||
          e.code == GoogleSignInExceptionCode.uiUnavailable) {
        throw const SignInCancelled();
      }
      throw StateError(_googleProblem(e));
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google did not return a sign-in token. Please try again.');
    return _finish(await api.googleLogin(idToken), 'google');
  }

  Future<UserSession> signInDev({
    required String provider,
    required String email,
    required String displayName,
  }) async =>
      _finish(await api.devLogin(email: email, displayName: displayName, provider: provider), provider);

  Future<UserSession> _finish(Map<String, dynamic> body, String provider) async {
    final session = UserSession.fromLogin(body, provider);
    await store.save(session);
    return session;
  }

  Future<void> signOut() async {
    await store.clear();
    // Forget the Google account choice so the picker shows next time (best effort).
    if (_googleReadyFor != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Best effort: the server side is already done.
      }
    }
  }

  /// Deletes the account on the server, then signs out locally.
  Future<void> deleteAccount() async {
    await api.deleteAccount();
    if (_googleReadyFor != null) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {
        // Best effort: the server side is already done.
      }
    }
    await store.clear();
  }

  static bool get appleAvailableOnThisDevice => Platform.isIOS;

  static String _googleProblem(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        // Usually the Android OAuth client is missing this build's SHA-1, or the package name differs.
        return 'Google sign-in is not set up for this app build yet. (${e.description ?? e.code.name})';
      default:
        return 'Google sign-in failed. Please try again.';
    }
  }
}
