import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('sends the bearer token and JSON, builds query strings', () async {
    late http.Request seen;
    final api = ApiClient(
      baseUrl: 'http://omnia.test/api',
      tokens: MemoryTokenStore('abc'),
      httpClient: MockClient((request) async {
        seen = request;
        return json({'ok': true});
      }),
    );
    await api.restoreToken();
    await api.post('/tasks', body: {'title': 'Réviser'});
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(seen.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(seen.body), {'title': 'Réviser'});
    expect(
      api.uri('/tasks', {'status': 'todo', 'priority': null, 'limit': 5}).toString(),
      'http://omnia.test/api/tasks?status=todo&limit=5',
    );
    expect(api.uri('/tasks').toString(), 'http://omnia.test/api/tasks');
  });

  test('maps the backend error envelope, including field details', () async {
    final api = ApiClient(
      baseUrl: 'http://omnia.test/api',
      tokens: MemoryTokenStore(),
      httpClient: MockClient(
        (_) async => json({
          'error': {
            'code': 'validation_error',
            'message': 'Some fields are invalid',
            'details': [
              {'field': 'body.title', 'message': 'String should have at least 1 character'},
            ],
          },
        }, 422),
      ),
    );
    final error = await api.post('/tasks', body: {'title': ''}).then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(error!.statusCode, 422);
    expect(error.code, 'validation_error');
    expect(error.fieldMessage('title'), contains('at least 1'));
  });

  test('401 with a token clears it and announces the expired session', () async {
    final store = MemoryTokenStore('old');
    final api = ApiClient(
      baseUrl: 'http://omnia.test/api',
      tokens: store,
      httpClient: MockClient((_) async => json({'error': {'code': 'unauthorized', 'message': 'expired'}}, 401)),
    );
    await api.restoreToken();
    var announced = 0;
    api.onUnauthorized.listen((_) => announced++);
    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', isTrue)));
    await pumpEventQueue();
    expect(announced, 1);
    expect(store.token, isNull);
    expect(api.hasToken, isFalse);
  });

  test('network failures become a friendly network error', () async {
    final api = ApiClient(
      baseUrl: 'http://omnia.test/api',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((_) async => throw http.ClientException('socket closed')),
    );
    await expectLater(
      api.get('/health'),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue)),
    );
  });

  test('task mapping round-trips through the backend shape', () {
    final task = taskFromApi({
      'id': 't1',
      'title': 'Lab report',
      'notes': 'Section 3',
      'priority': 'medium',
      'status': 'todo',
      'due_date': '2026-09-24',
      'due_time': '18:30:00',
      'estimated_minutes': 45,
      'category': 'study',
      'completed_at': null,
      'created_at': '2026-09-20T10:00:00Z',
      'updated_at': '2026-09-20T10:00:00Z',
    });
    expect(task.priority, TaskPriority.normal);
    expect(task.dueAt, DateTime(2026, 9, 24, 18, 30));
    expect(task.estimatedDuration, const Duration(minutes: 45));
    final body = taskToApi(task);
    expect(body['priority'], 'medium');
    expect(body['due_date'], '2026-09-24');
    expect(body['due_time'], '18:30');
    expect(body['category'], 'study');

    final allDay = taskToApi(task.copyWith(dueAt: DateTime(2026, 9, 25)));
    expect(allDay['due_time'], isNull);
    expect(taskToApi(task.copyWith(dueAt: null))['due_date'], isNull);
  });

  test('ApiTaskRepository pages through every task', () async {
    final all = [
      for (var i = 0; i < 250; i++)
        {
          'id': 't$i',
          'title': 'Task $i',
          'priority': 'low',
          'status': 'todo',
          'created_at': '2026-09-20T10:00:00Z',
        },
    ];
    final api = ApiClient(
      baseUrl: 'http://omnia.test/api',
      tokens: MemoryTokenStore('t'),
      httpClient: MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final limit = int.parse(request.url.queryParameters['limit']!);
        return json({
          'items': all.skip(offset).take(limit).toList(),
          'total': all.length,
          'limit': limit,
          'offset': offset,
        });
      }),
    );
    await api.restoreToken();
    final tasks = await ApiTaskRepository(api).getTasks();
    expect(tasks, hasLength(250));
    expect(tasks.last.id, 't249');
  });
}
