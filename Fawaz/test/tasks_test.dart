import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';

import 'support/fake_backend.dart';
import 'support/memory_task_repository.dart';

Task task(String id, {bool completed = false}) => Task(
  id: id,
  title: 'Task $id',
  completed: completed,
  createdAt: DateTime.utc(2025, 9, 23),
);

class FailingTaskRepository implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

Future<TaskController> pumpTasksPage(
  WidgetTester tester,
  TaskRepository repository,
) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TaskController(repository);
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: TaskScope(controller: controller, child: const TasksPage()),
    ),
  );
  return controller;
}

void main() {
  group('TaskController', () {
    test('loads, creates, updates, completes and deletes', () async {
      final controller = TaskController(MemoryTaskRepository(seed: [task('a')]));
      await controller.load();
      expect(controller.tasks.map((t) => t.id), ['a']);

      expect(await controller.create(task('b')), isTrue);
      expect(controller.tasks, hasLength(2));

      final renamed = controller.tasks.first.copyWith(title: 'Renamed');
      expect(await controller.update(renamed), isTrue);
      expect(controller.tasks.any((t) => t.title == 'Renamed'), isTrue);

      expect(await controller.setCompleted('a', true), isTrue);
      expect(controller.completedCount, 1);
      expect(controller.tasks.last.id, 'a', reason: 'completed sort last');
      expect(await controller.setCompleted('a', false), isTrue);
      expect(controller.completedCount, 0);

      expect(await controller.delete('a'), isTrue);
      expect(controller.tasks.map((t) => t.id), ['b']);
    });

    test('ignores a duplicate operation while one is in flight', () async {
      final repo = MemoryTaskRepository(seed: [task('a')]);
      final controller = TaskController(repo);
      await controller.load();
      final first = controller.setCompleted('a', true);
      expect(controller.isBusy('a'), isTrue);
      expect(await controller.setCompleted('a', false), isFalse);
      expect(await first, isTrue);
      expect((await repo.getTask('a')).completed, isTrue);
    });

    test('reports repository failures without throwing', () async {
      final controller = TaskController(FailingTaskRepository());
      await controller.load();
      expect(controller.loaded, isFalse);
      expect(controller.loadError, isNotNull);
      expect(await controller.create(task('x')), isFalse);
      expect(await controller.delete('x'), isFalse);
    });
  });

  group('TasksPage', () {
    testWidgets('renders repository data and completes a task', (tester) async {
      await pumpTasksPage(
        tester,
        MemoryTaskRepository(
          seed: [
            Task(
              id: 'a',
              title: 'Write report',
              priority: TaskPriority.high,
              estimatedDuration: const Duration(minutes: 90),
              createdAt: DateTime.utc(2025, 9, 23),
            ),
          ],
        ),
      );
      expect(find.text('Write report'), findsOneWidget);
      expect(find.textContaining('High priority'), findsOneWidget);
      expect(find.textContaining('1h 30m'), findsOneWidget);
      expect(find.textContaining('Due'), findsNothing);
      expect(find.text('0 of 1 completed'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 completed'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('create validates input, then adds the task', (tester) async {
      await pumpTasksPage(tester, MemoryTaskRepository(seed: []));
      expect(find.text('No tasks yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(SolidAction, 'Add task');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estimated minutes (optional)'),
        '0',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Enter a title'), findsOneWidget);
      expect(find.text('Enter whole minutes from 1 to 1440'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Buy groceries',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estimated minutes (optional)'),
        '25',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.byType(TasksPage), findsOneWidget);
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.textContaining('25m'), findsOneWidget);
    });

    testWidgets('edit pre-fills and saves; delete asks first', (tester) async {
      final controller = await pumpTasksPage(
        tester,
        MemoryTaskRepository(seed: [task('a')]),
      );
      await tester.tap(find.text('Task a'));
      await tester.pumpAndSettle();
      expect(find.text('Edit task'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Task a'),
        'Task renamed',
      );
      await tester.tap(find.widgetWithText(SolidAction, 'Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Task renamed'), findsOneWidget);

      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.tasks, hasLength(1));

      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No tasks yet'), findsOneWidget);
    });

    testWidgets('shows a retryable error state', (tester) async {
      await pumpTasksPage(tester, FailingTaskRepository());
      expect(find.text('Tasks could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('Home Tasks card opens Tasks; completing one updates the backend and Home', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..tasks.add({
        'id': 'task-1',
        'title': 'Submit lab report',
        'priority': 'high',
        'status': 'todo',
        'category': 'tasks',
        'created_at': '2026-09-24T03:00:00Z',
      });
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();

    expect(find.text('0 / 5'), findsOneWidget);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.byType(TasksPage), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(backend.tasks.single['status'], 'done');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('Creating a task sends it to the backend with the chosen fields', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Revise SQL joins');
    await tester.tap(find.text('High'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Estimated minutes (optional)'), '40');
    final save = find.widgetWithText(SolidAction, 'Add task');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Revise SQL joins'), findsOneWidget);
    final stored = backend.tasks.single;
    expect(stored['title'], 'Revise SQL joins');
    expect(stored['priority'], 'high');
    expect(stored['estimated_minutes'], 40);
    expect(stored['id'], isNot(startsWith('task-')), reason: 'the server assigns ids');
  });
}
