import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/token_store.dart';

/// The only place the app talks HTTP. Adds the bearer token, encodes JSON,
/// maps failures to [ApiException], and announces expired sessions.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this._tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final TokenStore _tokens;
  final http.Client _http;
  final _unauthorized = StreamController<void>.broadcast();
  String? _token;

  /// Fires when the backend rejects our token (expired, revoked, or the
  /// account is gone). The auth layer listens and returns to sign-in.
  Stream<void> get onUnauthorized => _unauthorized.stream;
  bool get hasToken => _token != null;

  Future<void> restoreToken() async => _token = await _tokens.read();

  Future<void> setToken(String? token) async {
    _token = token;
    await _tokens.write(token);
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) =>
      _send('POST', path, body: body, timeout: timeout);
  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// `baseUrl + path`, with null query values left out.
  Uri uri(String path, [Map<String, Object?>? query]) {
    final url = Uri.parse('$baseUrl$path');
    final params = <String, String>{
      for (final entry in (query ?? const <String, Object?>{}).entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    return params.isEmpty ? url : url.replace(queryParameters: params);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Duration? timeout,
  }) async {
    final request = http.Request(method, uri(path, query))
      ..headers['Accept'] = 'application/json';
    final token = _token;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final http.Response response;
    try {
      // The timeout covers reading the body too, not just the headers.
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw ApiException.network('OMNIA took too long to answer. Try again.');
    } catch (_) {
      throw ApiException.network();
    }

    final text = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } on FormatException {
        data = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    // Only a token we sent can expire; a failed sign-in is just a 401.
    if (response.statusCode == 401 && token != null) {
      await setToken(null);
      _unauthorized.add(null);
    }
    throw _errorFrom(response.statusCode, data);
  }

  static ApiException _errorFrom(int status, dynamic data) {
    final error = data is Map && data['error'] is Map
        ? Map<String, dynamic>.from(data['error'] as Map)
        : const <String, dynamic>{};
    final details = <FieldError>[
      for (final item
          in (error['details'] is List ? error['details'] as List : const []))
        if (item is Map)
          FieldError('${item['field'] ?? ''}', '${item['message'] ?? ''}'),
    ];
    return ApiException(
      statusCode: status,
      code: '${error['code'] ?? 'error'}',
      message: '${error['message'] ?? _fallbackMessage(status)}',
      details: details,
    );
  }

  static String _fallbackMessage(int status) => switch (status) {
    401 => 'Please sign in again.',
    404 => 'That item no longer exists.',
    429 => 'Too many requests. Please wait a moment.',
    >= 500 => 'OMNIA is having trouble right now. Try again shortly.',
    _ => 'Something went wrong. Please try again.',
  };

  void close() {
    _unauthorized.close();
    _http.close();
  }
}
