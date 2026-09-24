import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/token_store.dart';

/// An in-memory stand-in for the backend's auth endpoints, speaking the same
/// JSON and status codes as `Fawaz/backend/app/modules/auth`.
class FakeAuthBackend {
  /// The device's token storage, shared with every [client].
  final tokens = MemoryTokenStore();
  final requests = <String>[];
  bool offline = false;

  final _users = <String, Map<String, String>>{}; // email → account
  final _sessions = <String, String>{}; // token → email
  var _ids = 0;

  /// Adds an account. With [signedIn], this device already holds its token.
  void addUser(
    String name,
    String email,
    String password, {
    bool signedIn = false,
  }) {
    _users[email] = {
      'id': 'user-${++_ids}',
      'name': name,
      'password': password,
      'timezone': 'UTC',
    };
    if (signedIn) tokens.token = _issue(email);
  }

  bool hasUser(String email) => _users.containsKey(email);
  String? passwordOf(String email) => _users[email]?['password'];
  bool isValid(String token) => _sessions.containsKey(token);
  String? timezoneOf(String email) => _users[email]?['timezone'];

  /// Server-side revocation, e.g. the token expired.
  void endSessions(String email) =>
      _sessions.removeWhere((_, owner) => owner == email);

  ApiClient client() => ApiClient(
    baseUrl: 'http://omnia.test/api',
    tokens: tokens,
    httpClient: MockClient(_handle),
  );

  String _issue(String email) {
    final token = 'token-${++_ids}';
    _sessions[token] = email;
    return token;
  }

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api', '');
    requests.add('${request.method} $path');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    switch ((request.method, path)) {
      case ('POST', '/auth/register'):
        final email = '${body['email']}'.trim().toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          return _invalid('body.email', 'Enter a valid email address');
        }
        if ('${body['password']}'.length < 8) {
          return _invalid(
            'body.password',
            'String should have at least 8 characters',
          );
        }
        if (hasUser(email)) {
          return _error(
            409,
            'conflict',
            'An account with this email already exists',
          );
        }
        addUser('${body['display_name']}', email, '${body['password']}');
        _users[email]!['timezone'] = '${body['timezone']}';
        return _json(_tokenResponse(email), 201);
      case ('POST', '/auth/login'):
        final email = '${body['email']}'.trim().toLowerCase();
        if (passwordOf(email) != body['password']) {
          return _error(401, 'unauthorized', 'Incorrect email or password');
        }
        return _json(_tokenResponse(email));
    }

    final token = (request.headers['Authorization'] ?? '').replaceFirst(
      'Bearer ',
      '',
    );
    final email = _sessions[token];
    if (email == null) {
      return _error(
        401,
        'unauthorized',
        'Your session has expired or is invalid. Please sign in again.',
      );
    }
    switch ((request.method, path)) {
      case ('GET', '/auth/me'):
        return _json(_user(email));
      case ('POST', '/auth/logout-all'):
        endSessions(email);
        return http.Response('', 204);
      case ('POST', '/auth/change-password'):
        if (body['current_password'] != passwordOf(email)) {
          return _error(403, 'forbidden', 'Current password is incorrect');
        }
        if ('${body['new_password']}'.length < 8) {
          return _invalid(
            'body.new_password',
            'String should have at least 8 characters',
          );
        }
        _users[email]!['password'] = '${body['new_password']}';
        endSessions(email);
        return _json(_tokenResponse(email));
      case ('POST', '/auth/delete-account'):
        if (body['password'] != passwordOf(email)) {
          return _error(403, 'forbidden', 'Password is incorrect');
        }
        endSessions(email);
        _users.remove(email);
        return http.Response('', 204);
    }
    // Any other signed-in request (features aren't on the backend yet).
    return _json(<String, dynamic>{});
  }

  Map<String, dynamic> _user(String email) {
    final user = _users[email]!;
    return {
      'id': user['id'],
      'email': email,
      'created_at': '2026-09-24T08:00:00Z',
      'profile': {
        'display_name': user['name'],
        'timezone': user['timezone'],
        'username': null,
      },
    };
  }

  Map<String, dynamic> _tokenResponse(String email) => {
    'access_token': _issue(email),
    'token_type': 'bearer',
    'expires_in': 43200,
    'user': _user(email),
  };

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static http.Response _error(int status, String code, String message) =>
      _json({
        'error': {'code': code, 'message': message},
      }, status);

  static http.Response _invalid(String field, String message) => _json({
    'error': {
      'code': 'validation_error',
      'message': 'Some fields are invalid',
      'details': [
        {'field': field, 'message': message},
      ],
    },
  }, 422);
}
