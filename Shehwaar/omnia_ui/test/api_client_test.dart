import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_config.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/auth/token_store.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// A client whose every request is answered by [handler]; records requests.
({ApiClient api, List<http.Request> seen}) client(
  FutureOr<http.Response> Function(http.Request) handler, {
  TokenStore? tokens,
  Duration timeout = const Duration(seconds: 20),
}) {
  final seen = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://omnia.test/api',
    tokens: tokens ?? MemoryTokenStore(),
    timeout: timeout,
    httpClient: MockClient((request) async {
      seen.add(request);
      return handler(request);
    }),
  );
  addTearDown(api.close);
  return (api: api, seen: seen);
}

Future<ApiException> failure(Future<dynamic> call) => call.then<ApiException>(
  (_) => fail('expected an ApiException'),
  onError: (Object error) => error as ApiException,
);

/// Secure storage whose platform channel is broken.
class BrokenStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(PlatformException(code: 'unavailable'));
}

void main() {
  group('ApiConfig', () {
    test('an explicit base URL wins everywhere, without a trailing /', () {
      for (final release in [false, true]) {
        expect(
          ApiConfig.resolveBaseUrl(
            fromEnvironment: 'https://api.omnia.test/api/',
            releaseMode: release,
            platform: TargetPlatform.android,
          ),
          'https://api.omnia.test/api',
        );
      }
    });

    test('debug Android uses the emulator alias for the host', () {
      expect(
        ApiConfig.resolveBaseUrl(
          fromEnvironment: '',
          releaseMode: false,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'http://10.0.2.2:8000/api',
      );
    });

    test('debug web, iOS and desktop use localhost', () {
      expect(
        ApiConfig.resolveBaseUrl(
          fromEnvironment: '',
          releaseMode: false,
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        'http://localhost:8000/api',
        reason: 'Chrome on an Android host is still the browser',
      );
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          ApiConfig.resolveBaseUrl(
            fromEnvironment: '',
            releaseMode: false,
            isWeb: false,
            platform: platform,
          ),
          'http://localhost:8000/api',
        );
      }
    });

    test('release builds without a base URL have no default', () {
      expect(
        ApiConfig.resolveBaseUrl(fromEnvironment: '', releaseMode: true),
        isNull,
      );
    });

    test('this test run has no base URL and is not a release build', () {
      expect(ApiConfig.resolveBaseUrl(), isNotNull);
    });
  });

  group('ApiClient tokens', () {
    test('sends the restored bearer token', () async {
      final c = client(
        (_) => jsonResponse({}),
        tokens: MemoryTokenStore('abc'),
      );
      await c.api.restoreToken();
      expect(c.api.hasToken, isTrue);
      await c.api.get('/auth/me');
      expect(c.seen.single.headers['Authorization'], 'Bearer abc');
    });

    test('sends no Authorization header without a token', () async {
      final c = client((_) => jsonResponse({}));
      await c.api.restoreToken();
      expect(c.api.hasToken, isFalse);
      await c.api.get('/health');
      expect(c.seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('setToken stores the token and uses it; null clears both', () async {
      final store = MemoryTokenStore();
      final c = client((_) => jsonResponse({}), tokens: store);
      await c.api.setToken('new');
      expect(store.token, 'new');
      await c.api.get('/auth/me');
      expect(c.seen.last.headers['Authorization'], 'Bearer new');

      await c.api.setToken(null);
      expect(store.token, isNull);
      await c.api.get('/health');
      expect(c.seen.last.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('ApiClient JSON', () {
    test('encodes UTF-8 JSON bodies and decodes JSON responses', () async {
      final c = client(
        (_) => jsonResponse({
          'id': 't1',
          'title': 'Réviser',
          'tags': ['a'],
        }, 201),
      );
      final data = await c.api.post('/tasks', body: {'title': 'Réviser'});
      final request = c.seen.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://omnia.test/api/tasks');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(utf8.decode(request.bodyBytes)), {'title': 'Réviser'});
      expect(data, {
        'id': 't1',
        'title': 'Réviser',
        'tags': ['a'],
      });
    });

    test('sends no body or Content-Type when there is no body', () async {
      final c = client((_) => jsonResponse([1, 2]));
      expect(await c.api.get('/tasks'), [1, 2]);
      expect(c.seen.single.bodyBytes, isEmpty);
      expect(c.seen.single.headers.containsKey('Content-Type'), isFalse);
    });

    test('uses each HTTP method', () async {
      final c = client((_) => jsonResponse({}));
      await c.api.patch('/tasks/1', body: {'title': 'x'});
      await c.api.put('/sleep/2026-09-24', body: {'minutes': 420});
      await c.api.delete('/tasks/1');
      expect(c.seen.map((r) => r.method), ['PATCH', 'PUT', 'DELETE']);
    });

    test('an empty or non-JSON success body returns null', () async {
      final empty = client((_) => http.Response('', 204));
      expect(await empty.api.delete('/tasks/1'), isNull);
      final text = client((_) => http.Response('ok', 200));
      expect(await text.api.get('/health'), isNull);
    });

    test('builds query strings, leaving out null values', () async {
      final c = client((_) => jsonResponse({}));
      expect(
        c.api.uri('/tasks', {
          'status': 'todo',
          'priority': null,
          'limit': 5,
        }).toString(),
        'http://omnia.test/api/tasks?status=todo&limit=5',
      );
      expect(c.api.uri('/tasks').toString(), 'http://omnia.test/api/tasks');
      await c.api.get('/tasks', query: {'offset': 200});
      expect(c.seen.single.url.queryParameters, {'offset': '200'});
    });
  });

  group('ApiClient errors', () {
    test('maps the backend error envelope, including field details', () async {
      final c = client(
        (_) => jsonResponse({
          'error': {
            'code': 'validation_error',
            'message': 'Some fields are invalid',
            'details': [
              {
                'field': 'body.title',
                'message': 'String should have at least 1 character',
              },
              'not a map',
            ],
          },
        }, 422),
      );
      final error = await failure(c.api.post('/tasks', body: {'title': ''}));
      expect(error.statusCode, 422);
      expect(error.code, 'validation_error');
      expect(error.message, 'Some fields are invalid');
      expect(error.details, hasLength(1));
      expect(error.fieldMessage('title'), contains('at least 1'));
      expect(error.fieldMessage('due_date'), isNull);
      expect(friendlyError(error), 'Some fields are invalid');
    });

    test('falls back to a human message without an envelope', () async {
      Future<ApiException> status(int code) =>
          failure(client((_) => http.Response('<html>', code)).api.get('/x'));
      final notFound = await status(404);
      expect(notFound.isNotFound, isTrue);
      expect(notFound.code, 'error');
      expect(notFound.message, 'That item no longer exists.');
      expect((await status(429)).message, contains('Too many requests'));
      final down = await status(503);
      expect(down.isUnavailable, isTrue);
      expect(down.message, contains('having trouble'));
      expect((await status(400)).message, contains('Something went wrong'));
    });

    test('network failures become a friendly network error', () async {
      final c = client((_) => throw http.ClientException('socket closed'));
      final error = await failure(c.api.get('/health'));
      expect(error.isNetwork, isTrue);
      expect(error.statusCode, 0);
      expect(error.message, contains("Can't reach OMNIA"));
      expect(friendlyError(StateError('x')), contains('Something went wrong'));
    });

    test('a request that never answers times out as a network error', () async {
      final c = client(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50),
      );
      final error = await failure(c.api.get('/dashboard'));
      expect(error.isNetwork, isTrue);
      expect(error.message, contains('took too long'));
    });

    test('a per-call timeout overrides the client default', () async {
      final c = client((_) => Completer<http.Response>().future);
      final error = await failure(
        c.api.post('/ai/daily-plan', timeout: const Duration(milliseconds: 50)),
      );
      expect(error.message, contains('took too long'));
    });
  });

  group('ApiClient session expiry', () {
    test('401 with a token clears it and announces it once', () async {
      final store = MemoryTokenStore('old');
      final c = client(
        (_) => jsonResponse({
          'error': {'code': 'unauthorized', 'message': 'expired'},
        }, 401),
        tokens: store,
      );
      await c.api.restoreToken();
      var announced = 0;
      c.api.onUnauthorized.listen((_) => announced++);

      final error = await failure(c.api.get('/auth/me'));
      expect(error.isUnauthorized, isTrue);
      expect(error.message, 'expired');
      await pumpEventQueue();
      expect(announced, 1);
      expect(store.token, isNull);
      expect(c.api.hasToken, isFalse);

      // Signed out now: a further 401 is not another expiry.
      await failure(c.api.get('/auth/me'));
      await pumpEventQueue();
      expect(announced, 1);
    });

    test('401 without a token (a failed sign-in) is not an expiry', () async {
      final c = client(
        (_) => jsonResponse({
          'error': {'code': 'unauthorized', 'message': 'Wrong password'},
        }, 401),
      );
      var announced = 0;
      c.api.onUnauthorized.listen((_) => announced++);
      final error = await failure(
        c.api.post('/auth/login', body: {'email': 'a@b.c', 'password': 'x'}),
      );
      expect(error.message, 'Wrong password');
      await pumpEventQueue();
      expect(announced, 0);
    });
  });

  group('TokenStore', () {
    test('MemoryTokenStore reads what was written', () async {
      final store = MemoryTokenStore('a');
      expect(await store.read(), 'a');
      await store.write('b');
      expect(await store.read(), 'b');
      await store.write(null);
      expect(await store.read(), isNull);
    });

    test('SecureTokenStore persists across instances and deletes', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await SecureTokenStore().write('secret-token');
      expect(await SecureTokenStore().read(), 'secret-token');
      await SecureTokenStore().write(null);
      expect(await SecureTokenStore().read(), isNull);
    });

    test(
      'SecureTokenStore falls back to memory if the platform fails',
      () async {
        final store = SecureTokenStore(BrokenStorage());
        expect(await store.read(), isNull);
        await store.write('kept');
        expect(await store.read(), 'kept');
        await store.write(null);
        expect(await store.read(), isNull);
      },
    );
  });

  test('JSON helpers keep backend days as local calendar dates', () {
    expect(parseDay('2026-09-24'), DateTime(2026, 9, 24));
    expect(formatDay(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(formatDay(parseDay('0999-12-31')), '0999-12-31');
    expect(asMap({'a': 1}), isA<Map<String, dynamic>>());
    expect(
      asMapList([
        {'a': 1},
        {'b': 2},
      ]),
      [
        {'a': 1},
        {'b': 2},
      ],
    );
  });
}
