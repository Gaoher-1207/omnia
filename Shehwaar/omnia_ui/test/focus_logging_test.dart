import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

/// A Focus timer on a clock the test moves.
({FocusTimerController timer, void Function(Duration) advance}) clockTimer() {
  var now = DateTime(2026, 9, 24, 9);
  final timer = FocusTimerController(now: () => now);
  return (timer: timer, advance: (by) => now = now.add(by));
}

Future<FakeAuthBackend> start(
  WidgetTester tester,
  FocusTimerController timer,
) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = FakeAuthBackend()
    ..addUser('Sam', sam, 'password-123', signedIn: true)
    ..addUser('Ada', ada, 'ada-password');
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api, focusTimer: timer));
  await tester.pumpAndSettle();
  return backend;
}

Future<void> finishFocus(
  WidgetTester tester,
  FocusTimerController timer,
  void Function(Duration) advance,
) async {
  timer.start();
  advance(timer.phaseDuration);
  timer.tick();
  await tester.pumpAndSettle();
}

void main() {
  test('only a Focus phase that runs out is reported', () async {
    final (:timer, :advance) = clockTimer();
    addTearDown(timer.dispose);
    final reported = <Duration>[];
    timer.focusCompleted.listen((done) => reported.add(done.length));

    timer.start();
    timer.skip(); // skipped: not focus time
    timer.skip(); // back to focus
    timer.start();
    advance(const Duration(minutes: 10));
    timer.tick();
    timer.reset(); // reset part-way: not counted
    await Future<void>.delayed(Duration.zero);
    expect(reported, isEmpty);

    timer.start();
    advance(const Duration(minutes: 25));
    timer.tick();
    await Future<void>.delayed(Duration.zero);
    expect(reported, [const Duration(minutes: 25)]);

    // The break that follows is not study time either.
    timer.start();
    advance(const Duration(minutes: 5));
    timer.tick();
    await Future<void>.delayed(Duration.zero);
    expect(reported, hasLength(1));
  });

  testWidgets('a finished Focus phase is saved as study time and shown', (
    tester,
  ) async {
    final (:timer, :advance) = clockTimer();
    addTearDown(timer.dispose);
    final backend = await start(tester, timer);
    await finishFocus(tester, timer, advance);
    expect(backend.studyMinutesOn['$sam 2026-09-24'], 25);
    final dashboard = DashboardScope.of(tester.element(find.byType(HomePage)));
    expect(dashboard.dashboard?.today.studyMinutes, 25);
  });

  testWidgets('a failed save is retried, never double-counted', (tester) async {
    final (:timer, :advance) = clockTimer();
    addTearDown(timer.dispose);
    final backend = await start(tester, timer);
    backend.studyDown = true;
    await finishFocus(tester, timer, advance);
    expect(backend.studyMinutesOn['$sam 2026-09-24'], isNull);

    backend.studyDown = false;
    // Skip the break, then finish another Focus phase: both are saved once.
    timer.skip();
    await finishFocus(tester, timer, advance);
    expect(backend.studyMinutesOn['$sam 2026-09-24'], 50);
  });

  testWidgets('focus time never goes to the next account', (tester) async {
    final (:timer, :advance) = clockTimer();
    addTearDown(timer.dispose);
    final backend = await start(tester, timer);
    final auth = AuthScope.read(tester.element(find.byType(HomePage)));
    await auth.signOut();
    await tester.pumpAndSettle();
    await finishFocus(tester, timer, advance); // signed out: nobody's time
    await auth.signIn(ada, 'ada-password');
    await tester.pumpAndSettle();
    expect(backend.studyMinutesOn, isEmpty);
    timer.skip();
    await finishFocus(tester, timer, advance);
    expect(backend.studyMinutesOn.keys, ['$ada ${backend.todayFor(ada)}']);
  });
}
