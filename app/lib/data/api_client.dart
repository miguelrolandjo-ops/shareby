import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../l10n/l10n.dart';

/// The server could not be reached (no connection, timeout, DNS...). Treated as "offline".
class ApiUnreachable implements Exception {
  const ApiUnreachable([this.cause]);
  final Object? cause;

  @override
  String toString() => 'ApiUnreachable($cause)';
}

/// The server answered with an error.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Thin REST client for the Shareby API. The app never talks to PostgreSQL
/// directly — database credentials must not ship inside a mobile app.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokenProvider, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String? Function() tokenProvider;
  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _headers() {
    final token = tokenProvider();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on IOException catch (e) {
      throw ApiUnreachable(e);
    } on TimeoutException catch (e) {
      throw ApiUnreachable(e);
    } on http.ClientException catch (e) {
      throw ApiUnreachable(e);
    }

    var body = <String, dynamic>{};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        // Non-JSON error page (proxy, captive portal...). Fall through.
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final error = body['error'];
    throw ApiException(res.statusCode, error is String ? error : tr('Request failed ({code})', {'code': res.statusCode}));
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) =>
      _send(() => _client.get(_uri(path, query), headers: _headers()));

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) =>
      _send(() => _client.post(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<Map<String, dynamic>> _delete(String path) =>
      _send(() => _client.delete(_uri(path), headers: _headers()));

  // ------------------------------------------------------------ endpoints

  /// Which sign-in methods the server offers. Public, no sign-in needed.
  Future<Map<String, dynamic>> authConfig() => _get('/auth/config');

  /// Permanently deletes the signed-in account and what it stored on the server.
  Future<Map<String, dynamic>> deleteAccount() => _delete('/account');

  Future<Map<String, dynamic>> devLogin({
    required String email,
    required String displayName,
    required String provider,
  }) =>
      _post('/auth/dev', {'email': email, 'display_name': displayName, 'provider': provider});

  Future<Map<String, dynamic>> googleLogin(String idToken) => _post('/auth/google', {'id_token': idToken});

  Future<Map<String, dynamic>> appleLogin(String identityToken, {String? displayName}) =>
      _post('/auth/apple', {'identity_token': identityToken, 'display_name': displayName});

  Future<Map<String, dynamic>> push(List<Map<String, Object?>> ops) => _post('/sync/push', {'ops': ops});

  Future<Map<String, dynamic>> pull(String? since) =>
      _get('/sync/pull', since == null ? null : {'since': since});

  Future<Map<String, dynamic>> invite(String folderId, String email, String role) =>
      _post('/folders/$folderId/invites', {'email': email, 'role': role});

  Future<Map<String, dynamic>> preview(String url) => _get('/preview', {'url': url});

  /// The server's platform and title rules (see PlatformRules). Public, no sign-in needed.
  Future<Map<String, dynamic>> rules() => _get('/rules');
}
