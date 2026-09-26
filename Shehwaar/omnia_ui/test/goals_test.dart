import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/data/repository_exception.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/goals/goals_page.dart';

import 'support/select.dart';
import 'widget_test.dart' show startApp, tapText;

/// Measurable by default; pass `target: null` for completion-only.
Goal goal(
  String id, {
  double? current = 0,
  double? target = 10,
  String? unit = 'chapters',
  bool completed = false,
  DateTime? deadline,
}) => Goal(
  id: id,
  title: 'Goal $id',
  category: OmniaCategory.study,
  currentValue: target == null ? null : current,
  targetValue: target,
  unit: target == null ? null : unit,
  completed: completed,
  deadline: deadline,
);

Goal checkpoint(String id, {bool completed = false}) =>
    goal(id, target: null, completed: completed);

class FailingGoalRepository implements GoalRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

Future<GoalController> pumpGoalsPage(
  WidgetTester tester,
  GoalRepository repository, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = GoalController(repository);
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness: brightness),
      home: GoalScope(controller: controller, child: const GoalsPage()),
    ),
  );
  return controller;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> save(WidgetTester tester, String label) async {
  final button = find.widgetWithText(SolidAction, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('Goal', () {
    test('percentage is derived from current / target', () {
      expect(goal('a', current: 7, target: 12).percent, 58);
      expect(goal('a', current: 6, target: 10).percent, 60);
      expect(goal('a', current: 22.5, target: 30).percent, 75);
      expect(goal('a', current: 18000, target: 50000).percent, 36);
      expect(goal('a', current: 0).percent, 0);
      expect(goal('a', current: 9.99).percent, 99, reason: 'not 100 early');
    });

    test('above target shows 100% but keeps the real value', () {
      final g = goal('a', current: 32.5, target: 30, unit: 'kg');
      expect(g.percent, 100);
      expect(g.currentValue, 32.5);
      expect(g.completed, isFalse, reason: 'completion is explicit');
    });

    test('completion is independent of progress', () {
      final g = goal('a', current: 22.5, target: 30, completed: true);
      expect(g.percent, 75);
      final reopened = g.copyWith(completed: false);
      expect(reopened.currentValue, 22.5);
      expect(reopened.percent, 75);
    });

    test('completion-only goals carry no measurement', () {
      final g = checkpoint('a');
      expect(g.measurable, isFalse);
      expect(g.percent, isNull);
      expect(g.currentValue, isNull);
      expect(g.unit, isNull);
    });

    test('rejects invalid measurements', () {
      expect(() => goal('a', target: 0), throwsArgumentError);
      expect(() => goal('a', target: -5), throwsArgumentError);
      expect(() => goal('a', current: -1), throwsArgumentError);
      expect(() => goal('a', unit: '  '), throwsArgumentError);
      expect(() => goal('a', target: double.nan), throwsArgumentError);
      expect(
        () => Goal(
          id: 'a',
          title: 'A',
          category: OmniaCategory.study,
          unit: 'kg',
        ),
        throwsArgumentError,
        reason: 'a unit without a target is a fake measurement',
      );
    });

    test('copyWith switches between measurable and completion-only', () {
      final only = goal(
        'a',
        current: 6,
      ).copyWith(currentValue: null, targetValue: null, unit: null);
      expect(only.measurable, isFalse);
      final measured = only.copyWith(
        currentValue: 2.0,
        targetValue: 4.0,
        unit: 'kg',
      );
      expect(measured.percent, 50);
    });

    test('JSON round trips, and older JSON still loads', () {
      for (final g in [
        goal(
          'a',
          current: 22.5,
          target: 30,
          unit: 'kg',
          completed: true,
          deadline: DateTime(2025, 10, 10),
        ).copyWith(description: 'Units 1–5'),
        checkpoint('b'),
      ]) {
        expect(Goal.fromJson(g.toJson()).toJson(), g.toJson());
      }
      // The first Goal schema: no `completed`, current defaulted to 0.
      final legacy = Goal.fromJson({
        'id': 'x',
        'title': 'Y',
        'targetValue': 240,
        'unit': 'minutes',
        'category': 'study',
      });
      expect(legacy.measurable, isTrue);
      expect(legacy.currentValue, 0);
      expect(legacy.completed, isFalse);
      expect(
        Goal.fromJson({'id': 'x', 'title': 'Y', 'category': 'tasks'})
            .measurable,
        isFalse,
      );
    });
  });

  test('MockGoalRepository CRUD and completion', () async {
    final repo = MockGoalRepository(seed: [goal('a')]);
    final created = await repo.createGoal(checkpoint('b'));
    expect(await repo.getGoals(), hasLength(2));
    expect(() => repo.createGoal(created), throwsA(isA<RepositoryException>()));

    await repo.updateGoal(created.copyWith(title: 'Renamed'));
    expect((await repo.getGoal('b')).title, 'Renamed');
    expect((await repo.setCompleted('b', true)).completed, isTrue);
    expect((await repo.getGoal('b')).completed, isTrue);

    await repo.deleteGoal('b');
    expect(await repo.getGoals(), hasLength(1));
    expect(() => repo.getGoal('b'), throwsA(isA<RepositoryException>()));
  });

  group('GoalController', () {
    test(
      'creates, updates, records values, completes, reopens, deletes',
      () async {
        final controller = GoalController(
          MockGoalRepository(seed: [goal('a', current: 6)]),
        );
        await controller.load();

        expect(await controller.create(checkpoint('b')), isTrue);
        expect(controller.active.map((g) => g.id), ['a', 'b']);

        expect(
          await controller.update(controller.active.first.copyWith(title: 'X')),
          isTrue,
        );
        expect(controller.active.first.title, 'X');

        expect(await controller.setCurrentValue('a', 8.5), isTrue);
        expect(controller.active.first.currentValue, 8.5);
        expect(controller.active.first.percent, 85);
        expect(await controller.setCurrentValue('a', 12), isTrue);
        expect(controller.active.first.percent, 100);
        expect(controller.active.first.currentValue, 12);
        expect(controller.active.first.completed, isFalse);
        expect(await controller.setCurrentValue('a', -1), isFalse);
        expect(
          await controller.setCurrentValue('b', 3),
          isFalse,
          reason: 'completion-only goals have no value',
        );
        await controller.setCurrentValue('a', 4);

        expect(await controller.setCompleted('a', true), isTrue);
        expect(controller.active.map((g) => g.id), ['b']);
        expect(controller.completed.single.percent, 40);
        expect(await controller.setCompleted('a', false), isTrue);
        expect(controller.completed, isEmpty);
        final reopened = controller.active.firstWhere((g) => g.id == 'a');
        expect(reopened.currentValue, 4, reason: 'reopening keeps the value');

        expect(await controller.delete('a'), isTrue);
        expect(controller.active.map((g) => g.id), ['b']);
      },
    );

    test('orders active goals by nearest target date, undated last', () async {
      final controller = GoalController(
        MockGoalRepository(
          seed: [
            goal('none'),
            goal('late', deadline: DateTime(2026)),
            checkpoint('soon').copyWith(deadline: DateTime(2025, 10)),
            goal('none2'),
          ],
        ),
      );
      await controller.load();
      expect(controller.active.map((g) => g.id), [
        'soon',
        'late',
        'none',
        'none2',
      ]);
    });

    test('reports repository failures without throwing', () async {
      final controller = GoalController(FailingGoalRepository());
      await controller.load();
      expect(controller.loaded, isFalse);
      expect(controller.loadError, isNotNull);
      expect(await controller.create(goal('x')), isFalse);
      expect(await controller.setCompleted('x', true), isFalse);
      expect(await controller.setCurrentValue('x', 5), isFalse);
      expect(await controller.delete('x'), isFalse);
    });
  });

  group('GoalsPage', () {
    testWidgets('measurable cards show amount and percent once; '
        'completion-only cards show no progress', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpGoalsPage(
        tester,
        MockGoalRepository(
          seed: [
            Goal(
              id: 'press',
              title: 'Incline press',
              category: OmniaCategory.activity,
              currentValue: 22.5,
              targetValue: 30,
              unit: 'kg',
              deadline: DateTime(2025, 10, 30),
            ),
            Goal(
              id: 'project',
              title: 'Submit project',
              category: OmniaCategory.tasks,
              deadline: DateTime(2025, 11, 10),
            ),
          ],
        ),
      );
      expect(find.text('22.5 / 30 kg'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Activity  ·  By Thu, Oct 30'), findsOneWidget);
      expect(find.text('Tasks  ·  By Mon, Nov 10'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);

      // The card is one merged node: the amount is read as text and the
      // percentage once, as the progress bar's value.
      final card = tester.getSemantics(find.byType(LinearProgressIndicator));
      expect(card.label, contains('22.5 / 30 kg'));
      expect(card.label, contains('Incline press progress'));
      expect(card.label, isNot(contains('%')));
      expect(card.value, '75');
      semantics.dispose();
    });

    testWidgets('complete and reopen keep the numeric progress', (
      tester,
    ) async {
      await pumpGoalsPage(
        tester,
        MockGoalRepository(seed: [goal('a', current: 22.5, target: 30)]),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('0 active  ·  1 completed'), findsOneWidget);
      expect(find.text('22.5 / 30 chapters'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);

      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();
      expect(find.text('1 active  ·  0 completed'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
    });

    testWidgets('create validates numbers, previews, and saves decimals', (
      tester,
    ) async {
      await pumpGoalsPage(tester, MockGoalRepository(seed: []));
      expect(find.text('No goals yet'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);

      await save(tester, 'Add goal');
      expect(find.text('Enter a goal'), findsOneWidget);
      expect(find.text('Enter a number, like 6 or 22.5'), findsOneWidget);
      expect(find.text('Enter a number, like 10 or 30'), findsOneWidget);
      expect(find.text('Enter a unit, like kg or books'), findsOneWidget);

      await tester.enterText(field('Current value'), '-1');
      await tester.enterText(field('Target value'), '0');
      await save(tester, 'Add goal');
      expect(find.text('Can’t be negative'), findsOneWidget);
      expect(find.text('Must be more than 0'), findsOneWidget);
      await tester.enterText(field('Target value'), 'NaN');
      await save(tester, 'Add goal');
      expect(find.text('Enter a number, like 10 or 30'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.enterText(field('Goal'), 'Incline press');
      await tester.enterText(field('Current value'), '22.5');
      await tester.enterText(field('Target value'), '30');
      await tester.enterText(field('Unit'), 'kg');
      await tester.pump();
      // Read-only calculated feedback.
      expect(find.text('22.5 / 30 kg'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);

      await tester.enterText(field('Current value'), '32.5');
      await tester.pump();
      expect(find.text('32.5 / 30 kg'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await save(tester, 'Add goal');
      expect(find.byType(GoalsPage), findsOneWidget);
      expect(find.text('Incline press'), findsOneWidget);
      expect(find.text('32.5 / 30 kg'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('1 active  ·  0 completed'), findsOneWidget);
    });

    testWidgets('create a completion-only goal', (tester) async {
      final controller = await pumpGoalsPage(
        tester,
        MockGoalRepository(seed: []),
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(field('Goal'), 'Submit project');
      await tester.tap(find.text('Completion only'));
      await tester.pumpAndSettle();
      expect(field('Current value'), findsNothing);
      expect(field('Unit'), findsNothing);

      await save(tester, 'Add goal');
      expect(find.text('Submit project'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(controller.active.single.measurable, isFalse);
    });

    testWidgets('edit a value, switch type, complete; delete asks first', (
      tester,
    ) async {
      final controller = await pumpGoalsPage(
        tester,
        MockGoalRepository(seed: [goal('a', current: 6)]),
      );
      await tester.tap(find.text('Goal a'));
      await tester.pumpAndSettle();
      expect(find.text('Edit goal'), findsOneWidget);
      expect(find.text('6 / 10 chapters'), findsOneWidget);
      await tester.enterText(field('Current value'), '8');
      await save(tester, 'Save changes');
      expect(find.text('8 / 10 chapters'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);

      await tester.tap(find.text('Goal a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completion only'));
      await tester.pumpAndSettle();
      await save(tester, 'Save changes');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(controller.active.single.unit, isNull);

      await tester.tap(find.text('Goal a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measurable'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Current value'), '3');
      await tester.enterText(field('Target value'), '4');
      await tester.enterText(field('Unit'), 'books');
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await save(tester, 'Save changes');
      expect(find.text('3 / 4 books'), findsOneWidget);
      expect(controller.completed.single.percent, 75);

      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.completed, hasLength(1));

      await tester.tap(find.byTooltip('Goal actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No goals yet'), findsOneWidget);
    });

    testWidgets('shows a retryable error state', (tester) async {
      await pumpGoalsPage(tester, FailingGoalRepository());
      expect(find.text('Goals could not be loaded'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('renders without overflow at 200% text in '
          '${brightness.name} mode', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpGoalsPage(
          tester,
          MockGoalRepository(),
          brightness: brightness,
        );
        tester.view.physicalSize = const Size(360, 740);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Finish DBMS chapters'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Overflow here is horizontal; a tall view lays out every form row
        // at the narrow width without scrolling.
        tester.view.physicalSize = const Size(360, 2400);
        await tester.pumpAndSettle();
        expect(find.text('6 / 10 chapters'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // At this size the two choices open as a list, not squeezed segments.
        await pick(tester, 'Track progress', 'Completion only');
        expect(find.text('6 / 10 chapters'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Home previews measurable and completion-only goals from the '
      'shared controller', (tester) async {
    final semantics = tester.ensureSemantics();
    await startApp(tester);
    await tester.scrollUntilVisible(find.text('Finish DBMS chapters'), 200);
    expect(find.text('6 / 10 chapters  ·  60%'), findsOneWidget);
    final card = tester.getSemantics(find.text('6 / 10 chapters  ·  60%'));
    expect(card.label, contains('6 / 10 chapters'));
    expect(
      card.label,
      isNot(contains('%')),
      reason: 'the percentage is left to the progress bar',
    );
    expect(card.value, '60');
    expect(find.text('Incline Dumbbell Press'), findsOneWidget);
    expect(find.text('Submit final-year project'), findsNothing);

    await tapText(tester, 'Finish DBMS chapters');
    expect(find.byType(GoalsPage), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The completed goal left Home; the next nearest target took its place.
    expect(find.text('Finish DBMS chapters'), findsNothing);
    expect(find.text('Submit final-year project'), findsOneWidget);
    expect(find.text('Active  ·  By Mon, Nov 10'), findsOneWidget);
    semantics.dispose();
  });
}
