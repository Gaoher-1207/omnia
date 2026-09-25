import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

/// A backend with Sam signed in on this device, and a client holding his token.
Future<({FakeAuthBackend backend, ApiClient api})> signedIn() async {
  final backend = FakeAuthBackend()
    ..addUser('Sam', sam, 'password-123', signedIn: true)
    ..addUser('Ada', ada, 'ada-password');
  final api = backend.client();
  addTearDown(api.close);
  await api.restoreToken();
  return (backend: backend, api: api);
}

Task localTask({
  String title = 'Write report',
  DateTime? dueAt,
  Duration? estimate,
}) => Task(
  id: 'task-local-1',
  title: title,
  description: 'Section 3',
  priority: TaskPriority.high,
  category: OmniaCategory.study,
  dueAt: dueAt,
  estimatedDuration: estimate,
  createdAt: DateTime(2026, 9, 24),
);

Future<ApiException> failure(Future<dynamic> call) => call.then<ApiException>(
  (_) => fail('expected an ApiException'),
  onError: (Object error) => error as ApiException,
);

Future<void> startApiApp(WidgetTester tester, FakeAuthBackend backend) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> openTasks(WidgetTester tester) async {
  await tester.tap(find.text('Tasks'));
  await tester.pumpAndSettle();
}

void main() {
  group('Task mapping', () {
    test('backend JSON → Task', () {
      final task = taskFromApi({
        'id': '0b3c…uuid',
        'title': 'Lab report',
        'notes': 'Section 3',
        'priority': 'medium',
        'status': 'done',
        'due_date': '2026-09-24',
        'due_time': '18:30:00',
        'estimated_minutes': 45,
        'category': 'study',
        'completed_at': '2026-09-24T10:00:00+00:00',
        'created_at': '2026-09-20T10:00:00+00:00',
        'updated_at': '2026-09-24T10:00:00+00:00',
      });
      expect(task.id, '0b3c…uuid');
      expect(task.description, 'Section 3');
      expect(task.priority, TaskPriority.normal, reason: 'medium ↔ normal');
      expect(task.completed, isTrue);
      expect(task.dueAt, DateTime(2026, 9, 24, 18, 30));
      expect(task.estimatedDuration, const Duration(minutes: 45));
      expect(task.category, OmniaCategory.study);
      expect(task.createdAt, DateTime.utc(2026, 9, 20, 10));

      final bare = taskFromApi({
        'id': 'x',
        'title': 'T',
        'priority': 'low',
        'status': 'todo',
        'created_at': '2026-09-20T10:00:00+00:00',
      });
      expect(bare.completed, isFalse);
      expect(bare.dueAt, isNull);
      expect(bare.description, isNull);
      expect(bare.category, OmniaCategory.tasks);
    });

    test('Task → backend body: no id, status or user id', () {
      final body = taskToApi(
        localTask(
          dueAt: DateTime(2026, 9, 24, 18, 30),
          estimate: const Duration(minutes: 90),
        ),
      );
      expect(body.keys, isNot(contains('id')));
      expect(body.keys, isNot(contains('status')));
      expect(body.keys, isNot(contains('user_id')));
      expect(body, {
        'title': 'Write report',
        'notes': 'Section 3',
        'priority': 'high',
        'due_date': '2026-09-24',
        'due_time': '18:30',
        'estimated_minutes': 90,
        'category': 'study',
      });
      final allDay = taskToApi(localTask(dueAt: DateTime(2026, 9, 25)));
      expect(allDay['due_date'], '2026-09-25');
      expect(allDay['due_time'], isNull, reason: 'local 00:00 = all day');
    });
  });

  group('ApiTaskRepository against the fake backend', () {
    test('lists only the signed-in user\'s tasks', () async {
      final s = await signedIn();
      s.backend
        ..addTask(sam, 'Mine')
        ..addTask(ada, 'Not mine');
      final tasks = await ApiTaskRepository(s.api).getTasks();
      expect(tasks.map((t) => t.title), ['Mine']);
    });

    test('pages through every task, 200 at a time', () async {
      final all = [
        for (var i = 0; i < 250; i++)
          {
            'id': 't$i',
            'title': 'Task $i',
            'priority': 'low',
            'status': 'todo',
            'created_at': '2026-09-20T10:00:00+00:00',
          },
      ];
      final limits = <String>[];
      final api = ApiClient(
        baseUrl: 'http://omnia.test/api',
        tokens: MemoryTokenStore('t'),
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          limits.add('${query['limit']}@${query['offset']}');
          final offset = int.parse(query['offset']!);
          final limit = int.parse(query['limit']!);
          return http.Response(
            jsonEncode({
              'items': all.skip(offset).take(limit).toList(),
              'total': all.length,
              'limit': limit,
              'offset': offset,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await api.restoreToken();
      final tasks = await ApiTaskRepository(api).getTasks();
      expect(tasks, hasLength(250));
      expect(tasks.last.id, 't249');
      expect(limits, ['200@0', '200@200']);
    });

    test('create returns the server entity with its own id', () async {
      final s = await signedIn();
      final created = await ApiTaskRepository(s.api).createTask(
        localTask(
          dueAt: DateTime(2026, 9, 24, 18, 30),
          estimate: const Duration(minutes: 45),
        ),
      );
      expect(created.id, isNot('task-local-1'));
      expect(created.title, 'Write report');
      expect(created.priority, TaskPriority.high);
      expect(created.dueAt, DateTime(2026, 9, 24, 18, 30));
      final stored = s.backend.tasksOf(sam).single;
      expect(stored['id'], created.id);
      expect(stored['notes'], 'Section 3');
      expect(stored['due_time'], '18:30:00');
      expect(stored['estimated_minutes'], 45);
    });

    test('update edits fields and clears optional ones', () async {
      final s = await signedIn();
      final repo = ApiTaskRepository(s.api);
      final created = await repo.createTask(
        localTask(
          dueAt: DateTime(2026, 9, 24, 9),
          estimate: const Duration(minutes: 30),
        ),
      );
      final updated = await repo.updateTask(
        created.copyWith(
          title: 'Write final report',
          description: null,
          priority: TaskPriority.low,
          dueAt: null,
          estimatedDuration: null,
          category: OmniaCategory.tasks,
        ),
      );
      expect(updated.id, created.id);
      expect(updated.title, 'Write final report');
      expect(updated.description, isNull);
      expect(updated.dueAt, isNull);
      expect(updated.estimatedDuration, isNull);
      final stored = s.backend.tasksOf(sam).single;
      expect(stored['priority'], 'low');
      expect(stored['due_date'], isNull);
      expect(stored['due_time'], isNull);
      expect(stored['category'], 'tasks');
    });

    test('complete, then reopen', () async {
      final s = await signedIn();
      final repo = ApiTaskRepository(s.api);
      final id = s.backend.addTask(sam, 'Finish lab');

      expect((await repo.setCompleted(id, true)).completed, isTrue);
      expect(s.backend.tasksOf(sam).single['status'], 'done');
      expect(s.backend.tasksOf(sam).single['completed_at'], isNotNull);

      expect((await repo.setCompleted(id, false)).completed, isFalse);
      expect(s.backend.tasksOf(sam).single['status'], 'todo');
      expect(s.backend.tasksOf(sam).single['completed_at'], isNull);
      expect((await repo.getTask(id)).completed, isFalse);
    });

    test('delete removes the task; it is then not found', () async {
      final s = await signedIn();
      final repo = ApiTaskRepository(s.api);
      final id = s.backend.addTask(sam, 'Old task');
      await repo.deleteTask(id);
      expect(s.backend.tasksOf(sam), isEmpty);
      final error = await failure(repo.getTask(id));
      expect(error.isNotFound, isTrue);
    });

    test("another user's task can't be read, changed or deleted", () async {
      final s = await signedIn();
      final repo = ApiTaskRepository(s.api);
      final adasTask = s.backend.addTask(ada, 'Private');
      for (final call in [
        repo.getTask(adasTask),
        repo.setCompleted(adasTask, true),
        repo.deleteTask(adasTask),
      ]) {
        expect((await failure(call)).isNotFound, isTrue);
      }
      expect(s.backend.tasksOf(ada).single['status'], 'todo');
    });

    test('server and network failures surface as ApiException', () async {
      final s = await signedIn();
      final repo = ApiTaskRepository(s.api);
      s.backend.tasksDown = true;
      final down = await failure(repo.getTasks());
      expect(down.isUnavailable, isTrue);
      expect(down.message, 'Tasks are unavailable.');

      s.backend
        ..tasksDown = false
        ..offline = true;
      expect((await failure(repo.createTask(localTask()))).isNetwork, isTrue);
    });

    test('backend validation errors are reported per field', () async {
      final s = await signedIn();
      final error = await failure(
        ApiTaskRepository(s.api)
            .createTask(localTask(estimate: const Duration(minutes: 2000))),
      );
      expect(error.statusCode, 422);
      expect(error.fieldMessage('estimated_minutes'), isNotNull);
    });
  });

  group('TaskController on the API', () {
    test('keeps its state when the server fails', () async {
      final s = await signedIn();
      s.backend.addTask(sam, 'Existing');
      final controller = TaskController(ApiTaskRepository(s.api));
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.tasks.map((t) => t.title), ['Existing']);

      s.backend.tasksDown = true;
      expect(await controller.create(localTask()), isFalse);
      final id = controller.tasks.single.id;
      expect(await controller.setCompleted(id, true), isFalse);
      expect(controller.tasks.single.completed, isFalse);
      expect(await controller.delete(id), isFalse);
      expect(controller.tasks.map((t) => t.title), ['Existing']);

      await controller.load();
      expect(controller.loadError, isA<ApiException>());
    });

    test('ignores a second change to a task while one is in flight', () async {
      final s = await signedIn();
      final id = s.backend.addTask(sam, 'Once');
      final controller = TaskController(ApiTaskRepository(s.api));
      addTearDown(controller.dispose);
      await controller.load();
      final first = controller.setCompleted(id, true);
      expect(await controller.setCompleted(id, false), isFalse);
      expect(await first, isTrue);
      expect(s.backend.tasksOf(sam).single['status'], 'done');
    });
  });

  group('repository selection', () {
    test('mock dependencies use the in-memory task repository', () {
      expect(AppDependencies.mock().tasks, isA<MockTaskRepository>());
    });

    test('API dependencies use the API for tasks only', () async {
      final s = await signedIn();
      final deps = AppDependencies.api(s.api);
      expect(deps.tasks, isA<ApiTaskRepository>());
      expect(deps.goals, isA<MockGoalRepository>());
      expect(deps.study, isA<MockStudyRepository>());
    });

    testWidgets('mock mode wires MockTaskRepository into the app', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const OmniaApp());
      await tester.tap(find.text('SKIP →'));
      await tester.pumpAndSettle();
      final deps = AppDependenciesScope.of(
        tester.element(find.byType(HomePage)),
      );
      expect(deps.tasks, isA<MockTaskRepository>());
    });

    testWidgets('API mode wires ApiTaskRepository into the session', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      await startApiApp(tester, backend);
      final deps = AppDependenciesScope.of(
        tester.element(find.byType(HomePage)),
      );
      expect(deps.tasks, isA<ApiTaskRepository>());
      expect(deps.goals, isA<MockGoalRepository>());
    });
  });

  group('Tasks screen in API mode', () {
    testWidgets('create, edit, complete, reopen and delete reach the server', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      await startApiApp(tester, backend);
      expect(find.text('0 / 0'), findsOneWidget, reason: 'Home card');
      await openTasks(tester);
      expect(find.text('No tasks yet'), findsOneWidget);

      // Create.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Buy groceries',
      );
      await tester.tap(find.widgetWithText(SolidAction, 'Add task'));
      await tester.pumpAndSettle();
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(backend.tasksOf(sam).single['title'], 'Buy groceries');

      // Edit.
      await tester.tap(find.text('Buy groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Buy groceries'),
        'Buy vegetables',
      );
      await tester.tap(find.widgetWithText(SolidAction, 'Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Buy vegetables'), findsOneWidget);
      expect(backend.tasksOf(sam).single['title'], 'Buy vegetables');

      // Complete, then reopen.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 completed'), findsOneWidget);
      expect(backend.tasksOf(sam).single['status'], 'done');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(backend.tasksOf(sam).single['status'], 'todo');

      // Delete.
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(backend.tasksOf(sam), isEmpty);
    });

    testWidgets('tasks persist across an app restart', (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.addTask(sam, 'Survives restart');
      await startApiApp(tester, backend);
      expect(find.text('0 / 1'), findsOneWidget);

      // A fresh app with the same stored token and server.
      await tester.pumpWidget(const SizedBox());
      await startApiApp(tester, backend);
      await openTasks(tester);
      expect(find.text('Survives restart'), findsOneWidget);
    });

    testWidgets('a failed server change shows the existing error message', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.addTask(sam, 'Flaky');
      await startApiApp(tester, backend);
      await openTasks(tester);

      backend.tasksDown = true;
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not update the task. Try again.'),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true)
        ..tasksDown = true;
      backend.addTask(sam, 'Back soon');
      await startApiApp(tester, backend);
      await openTasks(tester);
      expect(find.text('Tasks could not be loaded'), findsOneWidget);

      backend.tasksDown = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Back soon'), findsOneWidget);
    });

    testWidgets('an expired session during a task change returns to sign-in', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.addTask(sam, 'Pending');
      await startApiApp(tester, backend);
      await openTasks(tester);

      backend.endSessions(sam);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TasksPage), findsNothing);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(
        find.text('Your session ended. Please sign in again.'),
        findsOneWidget,
      );
      expect(backend.tokens.token, isNull);
      expect(backend.tasksOf(sam).single['status'], 'todo');
    });
  });
}
