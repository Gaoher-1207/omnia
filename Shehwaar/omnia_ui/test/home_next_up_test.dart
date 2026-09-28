import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/features/home/data/api_dashboard_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/home/next_up.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';

import 'plan_api_test.dart' show payload;
import 'support/fake_auth_backend.dart';

const email = 'sam@example.com';

Map<String, dynamic> item(String title, String start, String end) => {
  ...((payload['items'] as List).first as Map<String, dynamic>),
  'title': title,
  'start': start,
  'end': end,
};

FakeAuthBackend noonBackend({String source = 'ollama', bool withPlan = true}) {
  final utc = DateTime.now().toUtc();
  final offset = 12 * 60 - utc.hour * 60 - utc.minute;
  final day = utc.add(Duration(minutes: offset)).toIso8601String().substring(0, 10);
  final backend = FakeAuthBackend()
    ..addUser('Sam', email, 'password-123', signedIn: true)
    ..dashboardOffsetMinutes = offset
    ..dashboardDate = day;
  backend.profileOf(email)!['time_format'] = '12h';
  if (withPlan) {
    backend.plans[email] = {
      ...payload,
      'plan_date': day,
      'source': source,
      'is_fallback': source == 'rules',
      'items': [
        item('Already ended', '11:00', '11:30'),
        item('Upcoming assignment', '12:30', '13:00'),
      ],
    };
  }
  return backend;
}

Future<void> start(WidgetTester tester, FakeAuthBackend backend) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> revealNextUp(WidgetTester tester, String text) async {
  await tester.dragUntilVisible(
    find.text(text),
    find.byType(HomePage),
    const Offset(0, -300),
  );
}

void main() {
  test('profile-zone time excludes ended blocks and recognizes in-progress', () async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, 'password-123', signedIn: true)
      ..dashboardDate = '2026-09-28'
      ..dashboardOffsetMinutes = 330;
    backend.plans[email] = {
      ...payload,
      'plan_date': '2026-09-28',
      'items': [item('Study', '08:00', '09:00')],
    };
    final api = backend.client();
    addTearDown(api.close);
    await api.restoreToken();
    final dashboard = await ApiDashboardRepository(api).getDashboard();
    expect(
      nextUp(dashboard, dashboard.aiPlan, DateTime.utc(2026, 9, 28, 3, 0))
          ?.inProgress,
      isTrue,
    );
    expect(
      nextUp(dashboard, dashboard.aiPlan, DateTime.utc(2026, 9, 28, 3, 30)),
      isNull,
    );
    expect(
      nextUp(dashboard, dashboard.aiPlan, DateTime.utc(2026, 9, 29, 3, 0)),
      isNull,
    );
  });

  for (final source in ['ollama', 'rules']) {
    testWidgets('Today reads $source suggestion from shared session snapshot', (
      tester,
    ) async {
      final backend = noonBackend(source: source);
      await start(tester, backend);
      await revealNextUp(tester, 'Upcoming assignment');
      expect(find.text('Already ended'), findsNothing);
      expect(find.text('12:30 PM–1:00 PM'), findsOneWidget);
      expect(
        backend.requests.where((r) => r == 'GET /ai/daily-plan'),
        isEmpty,
        reason: 'Dashboard already supplied the plan',
      );
      final controller = PlanScope.of(tester.element(find.byType(HomePage)));
      expect(controller.todayPlan?.source, source);
      await tester.tap(find.text('See all →').last);
      await tester.pumpAndSettle();
      expect(find.text('Upcoming assignment'), findsOneWidget);
      expect(
        backend.requests.where((r) => r == 'GET /ai/daily-plan'),
        isEmpty,
      );
    });
  }

  testWidgets('Today shows honest no-plan state and opens Plan', (tester) async {
    final backend = noonBackend(withPlan: false);
    await start(tester, backend);
    await revealNextUp(tester, 'No plan yet.');
    expect(find.text('Planning your day isn’t connected yet.'), findsNothing);
    await tester.ensureVisible(find.text('Open Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Plan'));
    await tester.pumpAndSettle();
    expect(find.text("Today's Plan"), findsOneWidget);
    expect(find.text('No plan for this date.'), findsOneWidget);
    expect(backend.requests.where((r) => r == 'POST /ai/daily-plan'), isEmpty);
  });

  testWidgets('Today never calls a finished item Next up', (tester) async {
    final backend = noonBackend();
    backend.plans[email]!['items'] = [item('Finished assignment', '11:00', '11:30')];
    await start(tester, backend);
    await revealNextUp(tester, 'No more planned blocks today.');
    expect(find.text('Finished assignment'), findsNothing);
  });

  testWidgets('Next up clears with the signed-out account session', (tester) async {
    final backend = noonBackend()
      ..addUser('Ada', 'ada@example.com', 'password-456');
    await start(tester, backend);
    await revealNextUp(tester, 'Upcoming assignment');
    final auth = AuthScope.of(tester.element(find.byType(HomePage)));
    await auth.signOut();
    await tester.pumpAndSettle();
    await auth.signIn('ada@example.com', 'password-456');
    await tester.pumpAndSettle();
    await revealNextUp(tester, 'No plan yet.');
    expect(find.text('Upcoming assignment'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Next up uses 24h time at 200% on a narrow $brightness phone', (
      tester,
    ) async {
      tester.view.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(
        tester.view.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = noonBackend();
      backend.profileOf(email)!['time_format'] = '24h';
      await start(tester, backend);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      await revealNextUp(tester, 'Upcoming assignment');
      expect(find.text('12:30–13:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
