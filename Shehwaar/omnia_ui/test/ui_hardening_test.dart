import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';
import 'package:omnia_ui/features/focus/widgets/focus_phase_feedback.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/features/areas/areas_page.dart';

import 'widget_test.dart' show startApp, tab, tapText;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('task checkbox is named by its task and visible in '
        '${brightness.name} mode', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TaskController(
        MockTaskRepository(
          seed: [
            Task(
              id: 'a',
              title: 'Write report',
              createdAt: DateTime.utc(2025, 9, 23),
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          home: TaskScope(controller: controller, child: const TasksPage()),
        ),
      );
      expect(
        tester.getSemantics(find.byType(Checkbox)),
        isSemantics(label: 'Write report', hasCheckedState: true),
      );
      // An open task sits on a yellow card in both themes: ink outline.
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).side?.color, ink);
      semantics.dispose();
    });
  }

  testWidgets('bottom navigation exposes the selected tab', (tester) async {
    final semantics = tester.ensureSemantics();
    await startApp(tester);
    expect(
      tester.getSemantics(find.text('Today')),
      isSemantics(label: 'Today', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Plan')),
      isSemantics(isButton: true, isSelected: false),
    );
    await tab(tester, Icons.calendar_month_outlined);
    expect(
      tester.getSemantics(find.text('Plan')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Today')),
      isSemantics(isSelected: false),
    );
    semantics.dispose();
  });

  testWidgets('Areas and Today share the live task count', (tester) async {
    await startApp(tester);
    expect(find.text('0 / 1'), findsOneWidget);
    await tab(tester, Icons.grid_view_rounded);
    expect(find.text('0 of 1'), findsOneWidget);

    await tab(tester, Icons.home_rounded);
    await tapText(tester, 'Tasks');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    await tab(tester, Icons.grid_view_rounded);
    expect(find.byType(AreasPage), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('the last onboarding page enters the app', (tester) async {
    await startApp(tester, skipOnboarding: false);
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENTER OMNIA'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('onboarding jumps between pages when animations are off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: OnboardingPage(onSkip: () {}),
      ),
    );
    await tester.tap(find.text('GET STARTED'));
    await tester.pump();
    expect(find.text('Next onboarding page').hitTestable(), findsOneWidget);
  });

  testWidgets('a completed revision undoes only when asked; reset is a menu', (
    tester,
  ) async {
    await startApp(tester);
    await tapText(tester, "View today's plan");
    await tapText(tester, 'DBMS Revision');

    await tapText(tester, 'Mark done');
    expect(find.text('Mark not done'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);

    await tapText(tester, 'More');
    expect(find.byType(AlertDialog), findsNothing, reason: 'menu, not dialog');
    await tapText(tester, 'Reset sub-tasks');
    expect(find.text('Reset sub-tasks?'), findsOneWidget);
    await tapText(tester, 'Cancel');
    await tester.scrollUntilVisible(find.text('Sub-tasks  3/3'), 180);
    expect(find.text('Sub-tasks  3/3'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mark not done'), -180);
    await tapText(tester, 'Mark not done');
    expect(find.text('Mark done'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sub-tasks  0/3'), 180);
    expect(find.text('Sub-tasks  0/3'), findsOneWidget);

    // Nothing to reset: the menu item is disabled.
    await tester.scrollUntilVisible(find.text('More'), -180);
    await tapText(tester, 'More');
    expect(
      tester
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, 'Reset sub-tasks'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished phase buzzes and is announced exactly once', (
    tester,
  ) async {
    var now = DateTime(2025, 9, 23, 10);
    final timer = FocusTimerController(now: () => now);
    addTearDown(timer.dispose);
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            FocusPhaseFeedback(controller: timer, child: child!),
        home: const SizedBox(),
      ),
    );

    timer.start();
    now = now.add(const Duration(minutes: 10));
    timer.tick();
    expect(haptics, isEmpty, reason: 'mid-phase ticks stay silent');

    now = now.add(const Duration(minutes: 15));
    timer.tick();
    await tester.pump();
    expect(haptics, hasLength(1));
    expect(tester.takeAnnouncements().map((a) => a.message), [
      phaseFinishedMessage(FocusPhase.focus),
    ]);
    // Existing behaviour is unchanged: counted, moved to an idle break.
    expect(timer.completedFocusSessions, 1);
    expect(timer.phase, FocusPhase.rest);
    expect(timer.running, isFalse);

    timer.tick();
    await tester.pump();
    expect(haptics, hasLength(1), reason: 'fires once per finish');
    expect(tester.takeAnnouncements(), isEmpty);

    timer.start();
    now = now.add(const Duration(minutes: 5));
    timer.tick();
    await tester.pump();
    expect(haptics, hasLength(2));
    expect(tester.takeAnnouncements().map((a) => a.message), [
      phaseFinishedMessage(FocusPhase.rest),
    ]);
  });

  testWidgets('screens render at 200% text on a small phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await startApp(tester, size: const Size(360, 740));
    expect(tester.takeException(), isNull);

    await tab(tester, Icons.grid_view_rounded);
    expect(tester.takeException(), isNull);
    await tab(tester, Icons.calendar_month_outlined);
    await tester.scrollUntilVisible(find.text('DBMS Revision'), 200);
    await tapText(tester, 'DBMS Revision');
    expect(find.byType(RevisionDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Start Focus Session'), 200);
    await tapText(tester, 'Start Focus Session');
    expect(find.byType(FocusTimerPage), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    await tapText(tester, 'Start focus');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Pause');
  });
}
