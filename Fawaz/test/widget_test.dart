import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/study/study_page.dart';
import 'package:omnia_ui/features/track/log_pages.dart';
import 'package:omnia_ui/features/track/track_page.dart';

import 'support/fake_backend.dart';

Future<FakeBackend> startApp(WidgetTester tester, {FakeBackend? backend}) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = backend ?? FakeBackend();
  await tester.pumpWidget(OmniaApp(dependencies: fake.dependencies()));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(find.text(text).first);
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
}

void expectTheme(WidgetTester tester, Type page, Brightness brightness) {
  final context = tester.element(find.byType(page));
  expect(Theme.of(context).brightness, brightness);
  expect(Theme.of(context).scaffoldBackgroundColor, brightness == Brightness.dark ? night : paper);
  for (final element in find.byType(HardCard).evaluate()) {
    final card = element.widget as HardCard;
    final material = tester.widget<Material>(
      find.descendant(of: find.byWidget(card), matching: find.byType(Material)).first,
    );
    expect(material.color, element.cardColor(card.color, prominent: card.prominent));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  test('Dark accent text maintains normal-text contrast', () {
    for (final background in [studyDark, tasksDark, activityDark, sleepDark]) {
      final ratio = (background.computeLuminance() + .05) / (ink.computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });

  test('Dark hero text maintains normal-text contrast', () {
    final ratio = (darkTextPrimary.computeLuminance() + .05) / (darkPrimary.computeLuminance() + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  testWidgets('Home shows the real dashboard, not sample data', (tester) async {
    final backend = FakeBackend()
      ..activity[FakeBackend.day(FakeBackend.today)] = {
        'id': 'a1',
        'day': FakeBackend.day(FakeBackend.today),
        'steps': 6240,
        'workout_done': false,
        'workout_minutes': 0,
        'workout_type': null,
      };
    await startApp(tester, backend: backend);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.textContaining('Sam.'), findsOneWidget);
    expect(find.text('6,240'), findsWidgets);
    expect(find.text('Not logged'), findsWidgets);
    expect(find.textContaining('SAMPLE'), findsNothing);
    expect(find.text('No exams coming up.'), findsOneWidget);
    expect(backend.requests, contains('GET /dashboard'));
  });

  testWidgets('A failed load shows an error with retry, never sample data', (tester) async {
    final backend = FakeBackend()..offline = true;
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach OMNIA"), findsOneWidget);
    backend.offline = false;
    await tapText(tester, 'Try again');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Planning the day, opening a study block and marking it done logs time', (tester) async {
    final backend = FakeBackend()
      ..subjects.add({'id': 's1', 'name': 'DBMS', 'color': null, 'created_at': '2026-09-01T00:00:00Z'});
    backend.topics.add({
      'id': 'b1',
      'title': 'Normalization',
      'kind': 'backlog',
      'status': 'pending',
      'estimated_minutes': 45,
      'completed_at': null,
      'created_at': '2026-09-01T00:00:00Z',
      'subject': {'id': 's1', 'name': 'DBMS', 'color': null},
    });
    await startApp(tester, backend: backend);
    await tapText(tester, 'Plan my day');
    expect(find.byType(PlanPage), findsOneWidget);
    expect(find.text('No plan for today yet'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'slept badly');
    await tapText(tester, 'Plan my day');
    expect(backend.plan, isNotNull);
    expect(find.text('DBMS: Revision'), findsOneWidget);

    await tapText(tester, 'DBMS: Revision');
    expect(find.byType(RevisionDetailPage), findsOneWidget);
    expect(find.text('Normalization'), findsOneWidget);
    expect(find.text('Sub-tasks  0/1'), findsOneWidget);

    await tapText(tester, 'Mark done');
    expect(backend.sessions, hasLength(1));
    expect(backend.sessions.single['duration_minutes'], 45);
    expect(backend.topics.single['status'], 'done');
    await tester.scrollUntilVisible(find.text('Sub-tasks  1/1'), 200);
    expect(find.text('Sub-tasks  1/1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tab(tester, Icons.home_rounded);
    expect(find.text('45m'), findsWidgets);
  });

  testWidgets('Track: logging steps, a workout and sleep saves to the backend', (tester) async {
    final backend = await startApp(tester);
    await tab(tester, Icons.bar_chart_rounded);
    expect(find.byType(TrackPage), findsOneWidget);

    await tapText(tester, 'Activity');
    expect(find.byType(ActivityLogPage), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Steps'), '9100');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Workout minutes'), '40');
    await tapText(tester, 'Save');
    final today = backend.activity[FakeBackend.day(FakeBackend.today)]!;
    expect(today['steps'], 9100);
    expect(today['workout_done'], isTrue);
    expect(today['workout_minutes'], 40);
    expect(find.text('9,100'), findsWidgets);

    await tapText(tester, 'Sleep');
    expect(find.byType(SleepLogPage), findsOneWidget);
    await tapText(tester, 'Good');
    await tapText(tester, 'Save');
    expect(backend.sleep[FakeBackend.day(FakeBackend.today)]!['quality'], 4);
    expect(find.text('7h'), findsWidgets);
  });

  testWidgets('Study: adding a subject goes to the backend; duplicates show the server message', (tester) async {
    final backend = await startApp(tester);
    await tab(tester, Icons.bar_chart_rounded);
    await tapText(tester, 'Study');
    expect(find.byType(StudyPage), findsOneWidget);
    expect(find.text('Add your subjects first'), findsOneWidget);
    await tapText(tester, 'Subjects');
    await tapText(tester, 'Add a subject');
    await tester.enterText(find.byType(TextField).last, 'Physics');
    await tapText(tester, 'Save');
    expect(backend.subjects.single['name'], 'Physics');
    expect(find.text('Physics'), findsOneWidget);

    await tapText(tester, 'Add a subject');
    await tester.enterText(find.byType(TextField).last, 'Physics');
    await tapText(tester, 'Save');
    expect(find.text('You already have a subject with this name'), findsOneWidget);
  });

  testWidgets('Insights shows backend streaks and achievements', (tester) async {
    final backend = FakeBackend();
    backend.sessions.add({
      'id': 'x',
      'session_date': FakeBackend.day(FakeBackend.today),
      'duration_minutes': 30,
      'subject': null,
    });
    await startApp(tester, backend: backend);
    await tab(tester, Icons.pie_chart_outline);
    expect(find.byType(InsightsPage), findsOneWidget);
    expect(find.text('Streaks'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('First step'), 300);
    expect(find.text('First step'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(backend.requests, contains('GET /progress'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('All tabs render real data in ${brightness.name} mode', (tester) async {
      await startApp(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tapText(tester, brightness == Brightness.dark ? 'Dark' : 'Light');
      expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness, brightness);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expectTheme(tester, HomePage, brightness);
      await tab(tester, Icons.calendar_month_outlined);
      expectTheme(tester, PlanPage, brightness);
      await tab(tester, Icons.bar_chart_rounded);
      expectTheme(tester, TrackPage, brightness);
      await tab(tester, Icons.pie_chart_outline);
      expectTheme(tester, InsightsPage, brightness);
    });
  }

  testWidgets('Signing out from Settings returns to the sign-in screen', (tester) async {
    final backend = await startApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tapText(tester, 'Sign out');
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(AuthPage), findsOneWidget);
    expect(backend.tokens.token, isNull);
  });
}
