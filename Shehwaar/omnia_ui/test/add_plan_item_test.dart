import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/data/mock_dashboard_repository.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/add_plan_item_page.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/domain/commitment_repository.dart';
import 'package:omnia_ui/features/plan/data/api_plan_repository.dart';
import 'package:omnia_ui/features/plan/data/mock_plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';

import 'widget_test.dart' show startApp;

final today = DateTime(2026, 9, 27);

/// A stand-in for the backend's plan endpoints, with its rules: refuse
/// overlaps and stale revisions, keep what was added for the next read.
class FakePlanServer {
  FakePlanServer({List<Map<String, dynamic>>? items})
    : plan = {
        'id': 'plan-1',
        'revision': 1,
        'plan_date': '2026-09-27',
        'created_at': '2026-09-27T08:00:00Z',
        'source': 'rules',
        'is_fallback': false,
        'summary': 'Assignment first.',
        'items':
            items ??
            [
              _item('a', '09:00', '09:30', 'Assignment', 'task'),
              _item('b', '14:00', '15:00', 'Gym', 'fitness'),
            ],
      };

  Map<String, dynamic> plan;
  final posts = <Map<String, dynamic>>[];
  final deletes = <Uri>[];
  Map<String, dynamic>? forcedError;
  int gets = 0;

  static Map<String, dynamic> _item(
    String key,
    String start,
    String end,
    String title,
    String category,
  ) => {
    'item_key': key,
    'start': start,
    'end': end,
    'category': category,
    'title': title,
  };

  static int _minutes(String value) =>
      int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));

  static http.Response json(Object value, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _error(int status, String code, String message) => json({
    'error': {'code': code, 'message': message},
  }, status);

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET') {
      gets++;
      return json(plan, 200);
    }
    if (request.method == 'DELETE') return _remove(request.url);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    posts.add(body);
    if (forcedError case final error?) {
      return json({'error': error}, error['status'] as int);
    }
    final start = _minutes(body['start'] as String);
    final end = start + (body['duration_minutes'] as int);
    for (final item in plan['items'] as List) {
      if (start < _minutes(item['end']) && end > _minutes(item['start'])) {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'plan_item_conflict',
              'message': 'This overlaps ${item['title']}. Nothing was moved.',
            },
          }),
          409,
        );
      }
    }
    final added = {
      'item_key': 'new-${posts.length}',
      'start': body['start'],
      'end':
          '${(end ~/ 60).toString().padLeft(2, '0')}:'
          '${(end % 60).toString().padLeft(2, '0')}',
      'category': body['category'],
      'title': body['title'] ?? 'Linked title',
      'task_id': body['task_id'],
      'subject_id': body['subject_id'],
      'manual': true,
    };
    plan = {
      ...plan,
      'revision': (plan['revision'] as int) + 1,
      'items': [...plan['items'] as List, added]
        ..sort((a, b) => (a['start'] as String).compareTo(b['start'])),
    };
    return json(plan, 200);
  }

  http.Response _remove(Uri url) {
    deletes.add(url);
    if (forcedError case final error?) {
      return json({'error': error}, error['status'] as int);
    }
    final key = url.pathSegments.last;
    final base = url.queryParameters['base_revision'];
    if (base != null && int.parse(base) != plan['revision']) {
      return _error(409, 'plan_stale', 'Your plan changed.');
    }
    final items = plan['items'] as List;
    if (!items.any((item) => item['item_key'] == key)) {
      return _error(409, 'plan_item_stale', 'This block is gone.');
    }
    plan = {
      ...plan,
      'revision': (plan['revision'] as int) + 1,
      'items': [
        for (final item in items)
          if (item['item_key'] != key) item,
      ],
    };
    return json(plan, 200);
  }
}

/// Fixed commitments for [today] only.
class FakeCommitments implements CommitmentRepository {
  FakeCommitments(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Commitment>> list() async => [
    for (final row in rows) Commitment.fromJson(row),
  ];
  @override
  Future<DayAvailability> availability({DateTime? day}) async =>
      DayAvailability.fromJson({
        'day': formatDay(day ?? today),
        'planning_start_minutes': 480,
        'planning_end_minutes': 1320,
        'commitments': rows,
        'free_intervals': <Object>[],
      });
  @override
  Future<Never> save(CommitmentDraft draft, {String? id}) =>
      throw UnimplementedError();
  @override
  Future<Never> delete(String id) => throw UnimplementedError();
}

class Harness {
  Harness(this.server, {List<Map<String, dynamic>> commitments = const []})
    : commitments = CommitmentController(FakeCommitments(commitments)),
      api = ApiClient(
        baseUrl: 'http://test/api',
        tokens: MemoryTokenStore(),
        httpClient: MockClient(server.handle),
      );
  final FakePlanServer server;
  final CommitmentController commitments;
  final ApiClient api;
  late final plans = PlanController(ApiPlanRepository(api));
  final tasks = TaskController(
    MockTaskRepository(
      seed: [
        Task(
          id: 'task-report',
          title: 'Write report',
          estimatedDuration: const Duration(minutes: 45),
          createdAt: DateTime.utc(2026, 9, 20),
        ),
      ],
    ),
  );
  final goals = GoalController(MockGoalRepository());
  final dashboard = DashboardController(MockDashboardRepository());
  late final study = StudyController(MockStudyRepository(), dashboard);

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    DateTime Function()? clock,
  }) async {
    final focus = FocusTimerController();
    addTearDown(() {
      for (final c in [
        plans,
        tasks,
        goals,
        dashboard,
        study,
        focus,
        commitments,
      ]) {
        c.dispose();
      }
      api.close();
    });
    await tasks.load();
    await goals.load();
    plans.seedToday(today, await ApiPlanRepository(api).getToday());
    await tester.pumpWidget(
      PlanScope(
        controller: plans,
        child: TaskScope(
          controller: tasks,
          child: GoalScope(
            controller: goals,
            child: StudyScope(
              controller: study,
              child: FocusTimerScope(
                controller: focus,
                child: CommitmentScope(
                  controller: commitments,
                  child: MaterialApp(
                    theme: buildAppTheme(brightness: brightness),
                    // A 24-hour picker: keyboard entry without AM/PM.
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                    home: Scaffold(body: DailyPlanView(today: today)),
                    routes: {
                      '/add': (_) => AddPlanItemPage(
                        day: today,
                        today: today,
                        clock: clock ?? () => DateTime(2026, 9, 27, 7, 50),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> openForm(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/add');
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // The form is a lazy list: build what is further down first.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) =>
    tapVisible(tester, find.widgetWithText(FilledButton, 'Add to plan'));

/// A picker field by its label (the label itself sits outside the tap target).
Finder field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

/// Picks [option] from the dropdown labelled [label].
Future<void> choose(WidgetTester tester, String label, String option) async {
  await tapVisible(tester, field(label));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The options a dropdown offers, read from its open sheet.
Future<List<String>> optionsOf(WidgetTester tester, String label) async {
  await tapVisible(tester, field(label));
  final sheet = find.byType(BottomSheet);
  final texts = tester
      .widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text)))
      .map((text) => text.data ?? '')
      .where((text) => text != label)
      .toList();
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  return texts;
}

/// Sets the start through the time picker's keyboard entry.
Future<void> setStart(WidgetTester tester, int hour, int minute) async {
  await tapVisible(tester, field('Start'));
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), hour.toString().padLeft(2, '0'));
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

double topOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  group('Add to plan', () {
    testWidgets(
      'an existing task is added in time order and survives a reload',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final harness = Harness(FakePlanServer());
        await harness.pump(tester);

        await tapVisible(tester, find.text('Add to plan'));
        expect(find.byType(AddPlanItemPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        // The same form, on a fixed clock.
        await openForm(tester);
        await choose(tester, 'Task', 'Write report');
        expect(find.text('45 min'), findsOneWidget, reason: 'its estimate');
        await setStart(tester, 11, 0);
        await save(tester);

        expect(find.byType(AddPlanItemPage), findsNothing);
        expect(harness.server.posts.single, {
          'category': 'task',
          'start': '11:00',
          'duration_minutes': 45,
          'task_id': 'task-report',
          'base_revision': 1,
        });
        expect(find.text('Added Write report to your plan.'), findsOneWidget);
        expect(find.textContaining('11:00–11:45'), findsOneWidget);
        expect(find.textContaining('Added by you'), findsOneWidget);
        expect(
          topOf(tester, 'Assignment'),
          lessThan(topOf(tester, 'Linked title')),
        );
        expect(topOf(tester, 'Linked title'), lessThan(topOf(tester, 'Gym')));

        await harness.plans.load();
        await tester.pumpAndSettle();
        expect(harness.server.gets, greaterThanOrEqualTo(2));
        expect(harness.plans.plan!.items.where((i) => i.manual), hasLength(1));
        expect(find.textContaining('11:00–11:45'), findsOneWidget);
      },
    );

    testWidgets('a new task is created in Tasks, then planned', (tester) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Task', 'Create new task…');
      await tester.enterText(find.byType(TextField), 'Pay rent');
      await tapVisible(tester, find.text('1h'));
      await setStart(tester, 16, 0);
      await save(tester);

      final created = harness.tasks.tasks.singleWhere(
        (task) => task.title == 'Pay rent',
      );
      expect(created.estimatedDuration, const Duration(hours: 1));
      expect(harness.server.posts.single['task_id'], created.id);
      expect(harness.server.posts.single['duration_minutes'], 60);
      expect(harness.plans.plan!.revision, 2);
    });

    testWidgets('a titled block from another area, with a custom length', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Area', 'Activity');
      await choose(tester, 'Workout', 'Running');
      await tapVisible(tester, find.byTooltip('5 minutes longer'));
      await tapVisible(tester, find.byTooltip('5 minutes longer'));
      expect(find.text('40 min'), findsOneWidget);
      await setStart(tester, 18, 30);
      expect(find.textContaining('18:30–19:10'), findsOneWidget);
      await save(tester);
      expect(harness.server.posts.single, {
        'category': 'fitness',
        'start': '18:30',
        'duration_minutes': 40,
        'title': 'Running',
        'base_revision': 1,
      });
    });

    testWidgets('an overlap is shown before saving and nothing is sent', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Area', 'Other');
      await tester.enterText(find.byType(TextField), 'Call home');
      await setStart(tester, 14, 30);
      expect(find.textContaining('This overlaps Gym'), findsOneWidget);
      expect(find.textContaining('Nothing will be moved'), findsOneWidget);
      await save(tester);
      expect(harness.server.posts, isEmpty);
      expect(find.byType(AddPlanItemPage), findsOneWidget);

      await setStart(tester, 15, 0);
      expect(find.textContaining('This overlaps'), findsNothing);
      await save(tester);
      expect(harness.server.posts, hasLength(1));
    });

    testWidgets('a conflict found by the server keeps the form and the plan', (
      tester,
    ) async {
      final server = FakePlanServer()
        ..forcedError = {
          'status': 409,
          'code': 'plan_item_conflict',
          'message': 'This overlaps Lab (10:00–11:00). Nothing was moved.',
        };
      final harness = Harness(server);
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Area', 'Other');
      await tester.enterText(find.byType(TextField), 'Call home');
      await setStart(tester, 10, 0);
      await save(tester);
      expect(
        find.text('This overlaps Lab (10:00–11:00). Nothing was moved.'),
        findsOneWidget,
      );
      expect(find.byType(AddPlanItemPage), findsOneWidget);
      expect(harness.plans.plan!.revision, 1);
      expect(find.widgetWithText(FilledButton, 'Add to plan'), findsOneWidget);
    });

    testWidgets('a stale plan is refreshed and the user is told', (
      tester,
    ) async {
      final server = FakePlanServer()
        ..forcedError = {
          'status': 409,
          'code': 'plan_stale',
          'message': 'Your plan changed.',
        };
      final harness = Harness(server);
      await harness.pump(tester);
      final reads = server.gets;
      await openForm(tester);
      await choose(tester, 'Area', 'Other');
      await tester.enterText(find.byType(TextField), 'Call home');
      await setStart(tester, 10, 0);
      await save(tester);
      expect(find.textContaining('it was refreshed'), findsOneWidget);
      expect(server.gets, reads + 1);
    });

    testWidgets('missing details and impossible times are caught first', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester, clock: () => DateTime(2026, 9, 27, 12, 0));
      await openForm(tester);
      await save(tester);
      expect(find.text('Choose a task, or add a new one.'), findsOneWidget);

      await choose(tester, 'Area', 'Other');
      await save(tester);
      expect(find.text('Add a title for this block.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Late call');
      await setStart(tester, 10, 0);
      expect(find.textContaining('already passed today'), findsOneWidget);

      await setStart(tester, 23, 30);
      await tapVisible(tester, find.text('2h'));
      expect(find.textContaining('run past midnight'), findsOneWidget);
      await save(tester);
      expect(harness.server.posts, isEmpty);
    });

    testWidgets('the item dropdown follows the chosen area', (tester) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      expect(await optionsOf(tester, 'Area'), [
        'Tasks',
        'Study',
        'Goals',
        'Activity',
        'Sleep & rest',
        'Other',
      ]);
      expect(await optionsOf(tester, 'Task'), [
        'Write report',
        'Create new task…',
      ]);
      await choose(tester, 'Task', 'Write report');

      await choose(tester, 'Area', 'Study');
      expect(find.text('Task'), findsNothing);
      expect(await optionsOf(tester, 'Subject'), [
        'DBMS',
        'Create new subject…',
      ]);
      await save(tester);
      expect(
        find.text('Choose a subject, or add a new one.'),
        findsOneWidget,
        reason: 'changing the area clears the earlier choice',
      );

      await choose(tester, 'Area', 'Sleep & rest');
      expect(await optionsOf(tester, 'Rest'), [
        ...restPresets,
        'Custom title…',
      ]);
      await choose(tester, 'Area', 'Other');
      expect(find.text('Rest'), findsNothing);
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    });

    testWidgets('a new subject is created from its dropdown, then planned', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Area', 'Study');
      await choose(tester, 'Subject', 'Create new subject…');
      await tester.enterText(find.byType(TextField), 'Physics');
      await setStart(tester, 16, 0);
      await save(tester);

      final physics = harness.study.subjects.singleWhere(
        (subject) => subject.name == 'Physics',
      );
      expect(harness.server.posts.single, {
        'category': 'study',
        'start': '16:00',
        'duration_minutes': 30,
        'subject_id': physics.id,
        'base_revision': 1,
      });
    });

    testWidgets('a goal or a custom title from a dropdown', (tester) async {
      final harness = Harness(FakePlanServer());
      await harness.pump(tester);
      await openForm(tester);
      await choose(tester, 'Area', 'Goals');
      final goal = harness.goals.active.first.title;
      await choose(tester, 'Goal', goal);
      expect(find.widgetWithText(TextField, 'Title'), findsNothing);
      await choose(tester, 'Goal', 'Custom title…');
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Plan');
      await setStart(tester, 16, 0);
      await save(tester);
      expect(harness.server.posts.single['title'], 'Plan');
      expect(harness.server.posts.single['category'], 'other');
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits a narrow phone at 200% text in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final harness = Harness(FakePlanServer());
        await harness.pump(tester, brightness: brightness);
        await openForm(tester);
        await choose(tester, 'Task', 'Write report');
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Add to plan'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Remove from plan', () {
    // Tall enough that the whole plan builds without scrolling.
    Future<void> pumpTall(Harness harness, WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return harness.pump(tester);
    }

    Finder square(String title) =>
        find.byTooltip('Not checked off: $title. Record what happened');

    Future<void> holdToRemove(WidgetTester tester, String title) async {
      await tester.ensureVisible(square(title));
      await tester.pumpAndSettle();
      await tester.longPress(square(title));
      await tester.pumpAndSettle();
    }

    Future<void> confirmRemove(WidgetTester tester) async {
      await tester.tap(find.text('Remove from plan…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
    }

    testWidgets('a tap records an outcome; it never removes', (tester) async {
      final harness = Harness(FakePlanServer());
      await pumpTall(harness, tester);
      await tester.tap(square('Gym'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Hold the square to remove this block'), findsOneWidget);
      expect(find.text('Remove from plan…'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(harness.server.deletes, isEmpty);
    });

    testWidgets('cancel at either step leaves the plan as it was', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await pumpTall(harness, tester);
      await holdToRemove(tester, 'Gym');
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Gym')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('14:00–15:00 · Sunday, September 27'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await holdToRemove(tester, 'Gym');
      await tester.tap(find.text('Remove from plan…'));
      await tester.pumpAndSettle();
      expect(find.text('Remove “Gym”?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.server.deletes, isEmpty);
      expect(find.text('Gym'), findsOneWidget);
      expect(harness.plans.plan!.revision, 1);
    });

    testWidgets('confirmed, a generated block is gone and stays gone', (
      tester,
    ) async {
      final harness = Harness(FakePlanServer());
      await pumpTall(harness, tester);
      await holdToRemove(tester, 'Assignment');
      await tester.tap(find.text('Remove from plan…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The task stays in Tasks.'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      final url = harness.server.deletes.single;
      expect(url.path, '/api/ai/daily-plan/2026-09-27/items/a');
      expect(url.queryParameters, {'base_revision': '1'});
      expect(find.text('Removed Assignment from your plan.'), findsOneWidget);
      expect(find.text('Assignment'), findsNothing);
      expect(find.text('Gym'), findsOneWidget);
      await harness.plans.load();
      await tester.pumpAndSettle();
      expect(find.text('Assignment'), findsNothing);
      expect(harness.plans.plan!.revision, 2);
    });

    testWidgets('a block added by hand, linked to a task, can be removed', (
      tester,
    ) async {
      final harness = Harness(
        FakePlanServer(
          items: [
            {
              'item_key': 'm',
              'start': '10:00',
              'end': '10:45',
              'category': 'task',
              'title': 'Write report',
              'task_id': 'task-report',
              'manual': true,
            },
          ],
        ),
      );
      await pumpTall(harness, tester);
      await holdToRemove(tester, 'Write report');
      expect(find.text('Added by you'), findsWidgets);
      await tester.tap(find.text('Remove from plan…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The task stays in Tasks.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(harness.server.deletes.single.pathSegments.last, 'm');
      expect(find.text('Write report'), findsNothing);
      expect(
        harness.tasks.tasks.single.completed,
        isFalse,
        reason: 'the task itself is untouched',
      );
    });

    testWidgets('fixed commitments offer no remove control', (tester) async {
      final harness = Harness(
        FakePlanServer(),
        commitments: [
          {
            'id': 'c1',
            'title': 'Lab',
            'category': 'class',
            'kind': 'one_off',
            'day': '2026-09-27',
            'start_minutes': 660,
            'end_minutes': 720,
            'enabled': true,
          },
        ],
      );
      await pumpTall(harness, tester);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.byTooltip(RegExp('Lab')), findsNothing);
      await tester.longPress(find.text('Lab'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from plan…'), findsNothing);
      expect(harness.server.deletes, isEmpty);
    });

    testWidgets('a changed plan is refreshed and nothing is removed', (
      tester,
    ) async {
      final server = FakePlanServer();
      final harness = Harness(server);
      await pumpTall(harness, tester);
      // Someone else changed the plan; this screen still shows revision 1.
      server.plan = {...server.plan, 'revision': 2};
      final reads = server.gets;
      await holdToRemove(tester, 'Gym');
      await confirmRemove(tester);
      expect(
        find.text(
          'Your plan changed, so it was refreshed. Nothing was removed.',
        ),
        findsOneWidget,
      );
      expect(server.gets, reads + 1);
      expect(harness.plans.plan!.revision, 2);
      expect(find.text('Gym'), findsOneWidget);
    });

    testWidgets('a server error says so and keeps the block', (tester) async {
      final server = FakePlanServer()
        ..forcedError = {
          'status': 503,
          'code': 'service_unavailable',
          'message': 'OMNIA is having trouble right now.',
        };
      final harness = Harness(server);
      await pumpTall(harness, tester);
      await holdToRemove(tester, 'Gym');
      await confirmRemove(tester);
      expect(find.textContaining('having trouble'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(harness.plans.plan!.revision, 1);
    });
  });

  group('mock mode', () {
    test('keeps added blocks for the session and refuses overlaps', () async {
      final repository = MockPlanRepository(null, today);
      final draft = ManualPlanItemDraft(
        category: 'other',
        startMinutes: 600,
        durationMinutes: 30,
        title: 'Call',
      );
      final first = await repository.addItem(today, draft);
      expect(first.source, 'manual');
      expect((await repository.getToday())!.items.single.title, 'Call');
      await expectLater(
        repository.addItem(today, draft, baseRevision: 1),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'plan_item_conflict',
          ),
        ),
      );
      await expectLater(
        repository.addItem(today, draft, baseRevision: 7),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'plan_stale'),
        ),
      );
      final done = await repository.recordOutcome(
        today,
        first.items.single.itemKey!,
        'done',
      );
      expect(done.items.single.outcome, 'done');
      expect((await repository.getToday())!.items.single.outcome, 'done');
    });

    testWidgets('the sample Plan tab adds a real block to another day', (
      tester,
    ) async {
      await startApp(tester);
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      expect(find.text('Morning Routine'), findsOneWidget, reason: 'sample');
      await tapVisible(tester, find.text('Add to plan'));
      await choose(tester, 'Task', 'Complete Assignment');
      await tapVisible(tester, field('Date'));
      await tester.tap(find.text('24'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.byType(AddPlanItemPage), findsNothing);
      expect(find.text('Complete Assignment'), findsOneWidget);
      expect(find.textContaining('09:00–10:00'), findsOneWidget);
      expect(find.text('Generate suggestion'), findsNothing);
      final plans = PlanScope.of(tester.element(find.byType(DailyPlanView)));
      expect(plans.selectedDate, DateTime(2025, 9, 24));
      await plans.load();
      await tester.pumpAndSettle();
      expect(find.text('Complete Assignment'), findsOneWidget);

      // A later day: checked off on the day, but it can be removed now.
      final square = find.byTooltip(
        'Complete Assignment: checked off on the day',
      );
      await tester.ensureVisible(square);
      await tester.pumpAndSettle();
      await tester.longPress(square);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from plan…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Complete Assignment'), findsNothing);
      await plans.load();
      await tester.pumpAndSettle();
      expect(find.text('Complete Assignment'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
