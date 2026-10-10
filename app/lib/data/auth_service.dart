import 'api_client.dart';
import 'models.dart';
import 'session_store.dart';

/// Signs the user in and stores the session.
///
/// Development builds use the server's /auth/dev endpoint (any email works), so two
/// emulators can play two friends. To go live, replace the body of [signIn]:
///   * Google: google_sign_in -> idToken -> api.googleLogin(idToken)
///   * Apple:  sign_in_with_apple -> identityToken -> api.appleLogin(identityToken)
/// Everything else (upload, sharing, sync) stays the same.
class AuthService {
  AuthService({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  Future<UserSession> signIn({
    required String provider,
    required String email,
    required String displayName,
  }) async {
    final body = await api.devLogin(email: email, displayName: displayName, provider: provider);
    final session = UserSession.fromLogin(body, provider);
    await store.save(session);
    return session;
  }

  Future<void> signOut() => store.clear();
}
