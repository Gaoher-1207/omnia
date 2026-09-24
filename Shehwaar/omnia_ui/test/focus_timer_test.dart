import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_preset.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';

/// Controller on a manually advanced clock; [tick] re-reads it.
class Harness {
  DateTime now = DateTime(2025, 9, 23, 10);
  late final timer = FocusTimerController(now: () => now);
  void advance(Duration by) {
    now = now.add(by);
    timer.tick();
  }
}

const min = Duration(minutes: 1);

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.timer.dispose());

  test('initial state is an idle 25 / 5 focus phase', () {
    final t = h.timer;
    expect(t.preset, FocusPreset.standard);
    expect(t.phase, FocusPhase.focus);
    expect(t.remaining, min * 25);
    expect(t.running || t.paused, isFalse);
    expect(t.completedFocusSessions, 0);
    expect(t.progress, 0);
  });

  test('selecting presets updates durations', () {
    h.timer.selectPreset(FocusPreset.deep);
    expect(h.timer.preset.label, '50 / 10');
    expect(h.timer.remaining, min * 50);
    h.timer.selectPreset(FocusPreset.standard);
    expect(h.timer.remaining, min * 25);
  });

  test('custom presets are validated', () {
    expect(FocusPreset.validateMinutes('30', max: 180), isNull);
    for (final bad in ['', '0', '-5', '2.5', 'abc', '181']) {
      expect(FocusPreset.validateMinutes(bad, max: 180), isNotNull);
    }
    expect(
      () => FocusPreset.custom(focusMinutes: 0, breakMinutes: 5),
      throwsArgumentError,
    );
    expect(
      () => FocusPreset.custom(focusMinutes: 30, breakMinutes: 61),
      throwsArgumentError,
    );
    final custom = FocusPreset.custom(focusMinutes: 40, breakMinutes: 8);
    expect(custom.isCustom, isTrue);
    h.timer.selectPreset(custom);
    expect(h.timer.remaining, min * 40);
  });

  test('start, pause, resume and reset follow the deadline', () {
    final t = h.timer..start();
    expect(t.running, isTrue);
    h.advance(min * 10);
    expect(t.remaining, min * 15);

    t.pause();
    expect(t.paused, isTrue);
    h.advance(min * 30); // Paused time does not count.
    expect(t.remaining, min * 15);

    t.resume();
    h.advance(min * 5);
    expect(t.remaining, min * 10);
    expect(t.progress, closeTo(.6, 1e-9));

    t.reset();
    expect(t.running || t.paused, isFalse);
    expect(t.remaining, min * 25);
  });

  test('countdown survives delayed ticks (deadline, not decrement)', () {
    h.timer.start();
    h.now = h.now.add(const Duration(minutes: 7, seconds: 30));
    expect(h.timer.remaining, const Duration(minutes: 17, seconds: 30));
  });

  test('focus completion counts a session and moves to an idle break', () {
    h.timer.start();
    h.advance(min * 26);
    expect(h.timer.completedFocusSessions, 1);
    expect(h.timer.phase, FocusPhase.rest);
    expect(h.timer.remaining, min * 5);
    expect(h.timer.running, isFalse, reason: 'break waits for the user');
    expect(h.timer.justFinished, FocusPhase.focus);
  });

  test('break completion moves back to focus', () {
    h.timer.skip();
    h.timer.start();
    h.advance(min * 5);
    expect(h.timer.phase, FocusPhase.focus);
    expect(h.timer.remaining, min * 25);
    expect(h.timer.justFinished, FocusPhase.rest);
    expect(h.timer.completedFocusSessions, 0);
  });

  test('skip focus and skip break do not count sessions', () {
    h.timer.start();
    h.timer.skip();
    expect(h.timer.phase, FocusPhase.rest);
    expect(h.timer.running, isFalse);
    h.timer.skip();
    expect(h.timer.phase, FocusPhase.focus);
    expect(h.timer.completedFocusSessions, 0);
  });

  test('repeated start keeps a single countdown', () {
    h.timer.start();
    h.advance(min);
    h.timer.start(); // Ignored: would otherwise move the deadline.
    h.timer.start();
    h.advance(min);
    expect(h.timer.remaining, min * 23);
  });

  testWidgets('real ticker drives completion and stops', (tester) async {
    await tester.runAsync(() async {
      final t = FocusTimerController(
        preset: const FocusPreset(
          name: 'Tiny',
          focus: Duration(milliseconds: 300),
          rest: Duration(minutes: 1),
        ),
      );
      t.start();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(t.completedFocusSessions, 1);
      expect(t.phase, FocusPhase.rest);
      expect(t.running, isFalse);
      t.dispose();
    });
  });

  group('FocusTimerPage', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: FocusTimerScope(
            controller: h.timer,
            child: const FocusTimerPage(),
          ),
        ),
      );
    }

    testWidgets('shows phase, countdown and controls', (tester) async {
      await pumpPage(tester);
      expect(find.text('FOCUS'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      await tester.tap(find.text('Start focus'));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      h.advance(const Duration(seconds: 23));
      await tester.pump();
      expect(find.text('24:37'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(find.text('BREAK'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
    });

    testWidgets('changing preset mid-session asks first; custom validates', (
      tester,
    ) async {
      await pumpPage(tester);
      h.timer.start();
      await tester.pump();
      await tester.tap(find.text('50 / 10'));
      await tester.pumpAndSettle();
      expect(find.text('Change timer?'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(h.timer.preset, FocusPreset.standard);
      expect(h.timer.running, isTrue);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Focus minutes'),
        '0',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1 to 180 minutes'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Focus minutes'),
        '40',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(h.timer.preset.label, '40 / 5');
      expect(find.text('40:00'), findsOneWidget);
      expect(find.text('Edit custom'), findsOneWidget);
    });
  });

  testWidgets('compact entry observes the same running timer', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        builder: (_, child) =>
            FocusTimerScope(controller: h.timer, child: child!),
        home: const Scaffold(body: FocusTimerEntry()),
      ),
    );
    expect(find.text('Open Focus Timer'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Open Focus Timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Time passes while the full timer page is closed.
    h.now = h.now.add(const Duration(minutes: 1, seconds: 19));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('23:41'), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(1421 / 1500, 1e-6));

    h.now = h.now.add(const Duration(seconds: 41));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('23:00'), findsOneWidget, reason: 'keeps updating');

    await tester.tap(find.text('23:00'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTimerPage), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget, reason: 'not reset');
    expect(find.text('Pause'), findsOneWidget, reason: 'still running');
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });

  testWidgets('app-level timer survives leaving the timer page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const OmniaApp());
    await tester.tap(find.text('SKIP →'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Focus Timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Open Focus Timer'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FocusTimerEntry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
  });

  testWidgets('Plan Focus view opens the Focus Timer', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const OmniaApp());
    await tester.tap(find.text('SKIP →'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Focus Timer'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTimerPage), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
  });
}
