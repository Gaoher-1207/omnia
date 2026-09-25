import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/data/api_dashboard_repository.dart';
import 'package:omnia_ui/features/home/data/mock_dashboard_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

FakeAuthBackend samSignedIn() => FakeAuthBackend()
  ..addUser('Sam', sam, 'password-123', signedIn: true)
  ..addUser('Ada', ada, 'ada-password');

Future<ApiClient> clientFor(FakeAuthBackend backend) async {
  final api = backend.client();
  addTearDown(api.close);
  await api.restoreToken();
  return api;
}

Future<ApiException> failure(Future<dynamic> call) => call.then<ApiException>(
  (_) => fail('expected an ApiException'),
  onError: (Object error) => error as ApiException,
);

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> startApiApp(WidgetTester tester, FakeAuthBackend backend) async {
  tallView(tester);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> pullToRefresh(WidgetTester tester) async {
  await tester.fling(find.byType(HomePage), const Offset(0, 400), 1000);
  await tester.pumpAndSettle();
}

int dashboardRequests(FakeAuthBackend backend) =>
    backend.requests.where((r) => r == 'GET /dashboard').length;

/// Sam's day: 1h 30m studied, 4,120 steps, no sleep logged, an exam ahead.
FakeAuthBackend samsDay() => samSignedIn()
  ..setToday(sam, {'study_minutes': 90, 'steps': 4120})
  ..setNextExam(
    sam,
    subject: 'Biology',
    title: 'Unit test',
    date: '2026-10-02',
    daysLeft: 8,
  );

void main() {
  group('Dashboard mapping', () {
    test('backend DashboardOut → Dashboard, ignoring later-phase fields', () {
      final dashboard = dashboardFromApi({
        'date': '2026-09-24',
        'greeting': 'evening',
        'display_name': 'Sam',
        'today': {
          'study_minutes': 90,
          'study_goal_minutes': 240,
          'tasks_completed': 1,
          'task_goal': 5,
          'steps': 4120,
          'step_goal': 8000,
          'workout_status': 'pending',
          'workout_minutes': 0,
          'sleep_minutes': 0,
          'sleep_goal_minutes': 450,
          'calories': 0,
          'calorie_goal': 2000,
        },
        'streaks': {'study': {}},
        'next_exam': {
          'id': 'e1',
          'title': 'Unit test',
          'subject_name': 'Biology',
          'exam_date': '2026-10-02',
          'days_left': 8,
        },
        'upcoming_tasks': [],
        'study_today': [],
        'ai_plan': null,
      });
      expect(dashboard.date, DateTime(2026, 9, 24), reason: 'a calendar day');
      expect(dashboard.greeting, 'evening');
      expect(dashboard.displayName, 'Sam');
      expect(dashboard.today.studyMinutes, 90);
      expect(dashboard.today.studyGoalMinutes, 240);
      expect(dashboard.today.steps, 4120);
      expect(dashboard.today.stepGoal, 8000);
      expect(dashboard.today.sleepMinutes, 0, reason: 'logged 0 is not null');
      expect(dashboard.today.sleepGoalMinutes, 450);
      expect(dashboard.nextExam!.subjectName, 'Biology');
      expect(dashboard.nextExam!.title, 'Unit test');
      expect(dashboard.nextExam!.date, DateTime(2026, 10, 2));
      expect(dashboard.nextExam!.daysLeft, 8);
      expect(dashboard.sample, isFalse);
    });

    test('no sleep logged and no exam stay null', () async {
      final dashboard = await ApiDashboardRepository(
        await clientFor(samSignedIn()),
      ).getDashboard();
      expect(dashboard.today.sleepMinutes, isNull);
      expect(dashboard.nextExam, isNull);
    });
  });

  group('ApiDashboardRepository against the fake backend', () {
    test("GET /dashboard returns the signed-in user's day", () async {
      final backend = samsDay()..setToday(ada, {'steps': 999});
      final dashboard = await ApiDashboardRepository(await clientFor(backend))
          .getDashboard();
      expect(backend.requests, ['GET /dashboard']);
      expect(dashboard.displayName, 'Sam');
      expect(dashboard.today.steps, 4120, reason: "not Ada's 999");
      expect(dashboard.nextExam!.subjectName, 'Biology');
    });

    test('without a session the server refuses', () async {
      final backend = FakeAuthBackend()..addUser('Sam', sam, 'password-123');
      final error = await failure(
        ApiDashboardRepository(await clientFor(backend)).getDashboard(),
      );
      expect(error.isUnauthorized, isTrue);
    });

    test('server and network failures surface as ApiException', () async {
      final backend = samSignedIn()..dashboardDown = true;
      final repo = ApiDashboardRepository(await clientFor(backend));
      expect((await failure(repo.getDashboard())).isUnavailable, isTrue);
      backend
        ..dashboardDown = false
        ..offline = true;
      expect((await failure(repo.getDashboard())).isNetwork, isTrue);
    });
  });

  test('MockDashboardRepository serves the labelled sample day', () async {
    final dashboard = await MockDashboardRepository().getDashboard();
    expect(dashboard.sample, isTrue);
    expect(dashboard.displayName, 'Shew');
    expect(dashboard.date, DateTime(2025, 9, 23));
    expect(dashboard.today.studyMinutes, 135);
    expect(dashboard.today.steps, 6240);
    expect(dashboard.today.sleepMinutes, 402);
    expect(dashboard.nextExam!.daysLeft, 8);
  });

  group('DashboardController', () {
    test('load, fail, retry; a failed reload keeps the last day', () async {
      final backend = samsDay()..dashboardDown = true;
      final controller = DashboardController(
        ApiDashboardRepository(await clientFor(backend)),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.dashboard, isNull);
      expect(controller.loadError, isA<ApiException>());

      backend.dashboardDown = false;
      await controller.load();
      expect(controller.loadError, isNull);
      expect(controller.dashboard!.today.steps, 4120);

      backend.dashboardDown = true;
      await controller.load();
      expect(controller.loadError, isA<ApiException>());
      expect(controller.dashboard!.today.steps, 4120);
    });
  });

  group('repository selection', () {
    test('mock dependencies use the sample dashboard', () {
      expect(AppDependencies.mock().dashboard, isA<MockDashboardRepository>());
    });

    test('API dependencies use GET /dashboard; Goals stay local', () async {
      final deps = AppDependencies.api(await clientFor(samSignedIn()));
      expect(deps.dashboard, isA<ApiDashboardRepository>());
      expect(deps.tasks, isA<ApiTaskRepository>());
      expect(deps.goals, isA<MockGoalRepository>());
    });
  });

  group('Home and Track', () {
    testWidgets('mock mode keeps the sample day, labelled', (tester) async {
      tallView(tester);
      await tester.pumpWidget(const OmniaApp());
      await tester.tap(find.text('SKIP →'));
      await tester.pumpAndSettle();

      expect(find.text('Good morning,\nShew.'), findsOneWidget);
      expect(find.text('Tuesday, September 23  ·  SAMPLE DAY'), findsOneWidget);
      expect(find.text('Your DBMS exam is in 8 days.'), findsOneWidget);
      for (final text in ['2h 15m', '/ 4h', '6,240', '/ 8,000', '6h 42m']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('SAMPLE'), findsOneWidget, reason: 'the card tag only');

      await openTab(tester, 'Track');
      expect(find.text('Your day at a glance  ·  SAMPLE DATA'), findsOneWidget);
      for (final text in ['4h goal', '8,000 steps', '6h 42m', '8h goal']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('SAMPLE'), findsNothing);
    });

    testWidgets('API mode shows the real day on Home and Track', (
      tester,
    ) async {
      final backend = samsDay();
      backend
        ..addTask(sam, 'Done', done: true)
        ..addTask(sam, 'Open');
      await startApiApp(tester, backend);

      expect(find.text('Good morning,\nSam.'), findsOneWidget);
      expect(find.text('Thursday, September 24'), findsOneWidget);
      expect(find.text('Your Biology exam is in 8 days.'), findsOneWidget);
      expect(find.text('Unit test  ·  Friday, October 2'), findsOneWidget);
      for (final text in ['1h 30m', '/ 4h', '4,120', '/ 8,000', 'Not logged']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('/ 8h'), findsOneWidget);
      // No sample figures leak into API mode.
      for (final text in [
        'Good morning,\nShew.',
        'Your DBMS exam is in 8 days.',
        '2h 15m',
        '6,240',
        '6h 42m',
      ]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.textContaining('SAMPLE DAY'), findsNothing);
      expect(find.text('SAMPLE'), findsNothing, reason: 'the card is real');
      // Only Next up is still the sample plan, and it says so.
      await tester.dragUntilVisible(
        find.textContaining('Next up'),
        find.byType(HomePage),
        const Offset(0, -300),
      );
      expect(find.text('SAMPLE'), findsOneWidget);
      // Tasks keep their all-time meaning, not the dashboard's 1 of 5 goal.
      expect(find.text('1 / 2'), findsOneWidget);

      await openTab(tester, 'Track');
      expect(find.text('Your day at a glance'), findsOneWidget);
      for (final text in ['1h 30m', '4h goal', '4,120', '8,000 steps']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Not logged'), findsOneWidget);
      expect(find.text('SAMPLE'), findsOneWidget, reason: "Today's activity");
      expect(dashboardRequests(backend), 1, reason: 'Track shares Home’s');
    });

    testWidgets('the API-mode labels fit 200% text on a small phone', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = samsDay().client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(HomePage), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('SAMPLE'), findsOneWidget, reason: 'reached Next up');
      await openTab(tester, 'Track');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no upcoming exam and logged sleep', (tester) async {
      final backend = samSignedIn()..setToday(sam, {'sleep_minutes': 450});
      await startApiApp(tester, backend);
      expect(find.text('No exams coming up.'), findsOneWidget);
      expect(find.text('Upcoming exams will count down here.'), findsOneWidget);
      expect(find.textContaining('DBMS exam'), findsNothing);
      expect(find.text('7h 30m'), findsOneWidget);
      expect(find.text('Not logged'), findsNothing);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final backend = samsDay()..dashboardDown = true;
      await startApiApp(tester, backend);
      expect(find.text("Couldn't load today."), findsOneWidget);
      expect(find.text('4,120'), findsNothing);

      backend.dashboardDown = false;
      await tester.tap(find.widgetWithText(SolidAction, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load today."), findsNothing);
      expect(find.text('4,120'), findsOneWidget);
    });

    testWidgets('pull to refresh; a failed refresh keeps the day and says so', (
      tester,
    ) async {
      final backend = samsDay();
      await startApiApp(tester, backend);
      backend.setToday(sam, {'steps': 5000});
      await pullToRefresh(tester);
      expect(find.text('5,000'), findsOneWidget);

      backend.dashboardDown = true;
      await pullToRefresh(tester);
      expect(find.text('5,000'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('returning to the app refreshes the day', (tester) async {
      final backend = samsDay();
      await startApiApp(tester, backend);
      backend.setToday(sam, {'steps': 7000});
      // Backgrounded and brought back, one platform step at a time.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text('7,000'), findsOneWidget);
    });

    testWidgets("the next user never sees the previous user's day", (
      tester,
    ) async {
      final backend = samsDay()..setToday(ada, {'steps': 999});
      await startApiApp(tester, backend);
      final samsController = DashboardScope.of(
        tester.element(find.byType(HomePage)),
      );
      expect(find.text('4,120'), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ListTile, 'Sign out'));
      await tester.tap(find.widgetWithText(ListTile, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), ada);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'ada-password',
      );
      await tester.tap(find.widgetWithText(SolidAction, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Good morning,\nAda.'), findsOneWidget);
      expect(find.text('999'), findsOneWidget);
      expect(find.text('4,120'), findsNothing);
      expect(find.textContaining('Biology'), findsNothing);
      expect(
        DashboardScope.of(tester.element(find.byType(HomePage))),
        isNot(same(samsController)),
      );
    });

    testWidgets('an expired session while refreshing returns to sign-in', (
      tester,
    ) async {
      final backend = samsDay();
      await startApiApp(tester, backend);
      backend.endSessions(sam);
      await pullToRefresh(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HomePage), findsNothing);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(
        find.text('Your session ended. Please sign in again.'),
        findsOneWidget,
      );
      expect(backend.tokens.token, isNull);
    });
  });
}
