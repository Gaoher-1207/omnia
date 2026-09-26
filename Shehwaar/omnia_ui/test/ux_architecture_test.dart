import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/choice_segments.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/features/areas/areas_page.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';
import 'package:omnia_ui/features/goals/goals_page.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/plan/widgets/timeline_row.dart';
import 'package:omnia_ui/features/settings/profile_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/study/study_page.dart';
import 'package:omnia_ui/features/tasks/task_form_page.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';

import 'support/select.dart';
import 'track_logging_test.dart'
    show backend, lastPut, reveal, sam, save, startApp, tapCard, today;

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  group('typography', () {
    for (final brightness in Brightness.values) {
      test('Archivo is the default everywhere (${brightness.name})', () {
        final theme = buildAppTheme(brightness: brightness);
        // Styles handed to components replace the inherited one, so each
        // must name the family or it falls back to the platform font.
        for (final style in [
          theme.textTheme.bodyMedium,
          theme.textTheme.titleLarge,
          theme.textTheme.labelLarge,
          theme.appBarTheme.titleTextStyle,
          theme.snackBarTheme.contentTextStyle,
          theme.inputDecorationTheme.floatingLabelStyle,
          theme.segmentedButtonTheme.style?.textStyle?.resolve({}),
        ]) {
          expect(style?.fontFamily, archivo);
        }
      });
    }

    test('Space Mono is only the utility styles', () {
      expect(OmniaText.label.fontFamily, spaceMono);
      expect(OmniaText.meta.fontFamily, spaceMono);
    });

    testWidgets('tags use the utility face', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const LabelTag(text: 'SAMPLE'),
        ),
      );
      expect(
        tester.widget<Text>(find.text('SAMPLE')).style?.fontFamily,
        spaceMono,
      );
    });
  });

  testWidgets('segments become a list at large text sizes', (tester) async {
    var value = 'a';
    Widget app(double scale) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: StatefulBuilder(
            builder: (context, setState) => ChoiceSegments<String>(
              label: 'Pick',
              options: const [
                SelectOption('a', 'Alpha'),
                SelectOption('b', 'Bravo'),
              ],
              selected: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(1));
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    await tester.pumpWidget(app(2));
    expect(find.byType(SegmentedButton<String>), findsNothing);
    await pick(tester, 'Pick', 'Bravo');
    expect(value, 'b');
  });

  group('root navigation', () {
    testWidgets('the tabs are Today, Plan, Areas and Insights', (tester) async {
      await startApp(tester, backend());
      for (final name in ['Today', 'Plan', 'Areas', 'Insights']) {
        expect(find.text(name).hitTestable(), findsWidgets, reason: name);
      }
      expect(find.text('Home'), findsNothing);
      expect(find.text('Track'), findsNothing);
    });

    testWidgets('each tab keeps its own stack under the tab bar', (
      tester,
    ) async {
      await startApp(tester, backend());
      await openTab(tester, 'Areas');
      await tapCard(tester, 'Tasks', page: AreasPage);
      expect(find.byType(TasksPage), findsOneWidget);

      await openTab(tester, 'Today');
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
      await openTab(tester, 'Areas');
      expect(find.byType(TasksPage), findsOneWidget, reason: 'kept');

      // Choosing the open tab again returns it to its first screen.
      await openTab(tester, 'Areas');
      expect(find.byType(TasksPage), findsNothing);
      expect(find.byType(AreasPage).hitTestable(), findsOneWidget);
    });

    testWidgets('system back leaves an area before it leaves the app', (
      tester,
    ) async {
      await startApp(tester, backend());
      await openTab(tester, 'Areas');
      await tapCard(tester, 'Goals', page: AreasPage);
      expect(find.byType(GoalsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GoalsPage), findsNothing);
      expect(find.byType(AreasPage).hitTestable(), findsOneWidget);
    });

    testWidgets('forms cover the tab bar; hubs sit under it', (tester) async {
      await startApp(tester, backend());
      await tapCard(tester, 'Activity');
      expect(find.text('Areas').hitTestable(), findsNothing, reason: 'form');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapCard(tester, 'Tasks');
      expect(find.text('Areas').hitTestable(), findsOneWidget, reason: 'hub');
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormPage), findsOneWidget);
      expect(find.text('Areas').hitTestable(), findsNothing, reason: 'form');
    });

    testWidgets('a running focus session survives moving around', (
      tester,
    ) async {
      await startApp(tester, backend());
      await tapCard(tester, 'Study');
      final start = find.text('Open Focus Timer');
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start focus'));
      await tester.pump();
      final timer = FocusTimerScope.of(
        tester.element(find.byType(FocusTimerPage)),
      );
      expect(timer.inProgress, isTrue);

      await openTab(tester, 'Areas');
      await openTab(tester, 'Today');
      await openTab(tester, 'Today'); // back to Today's first screen
      await openTab(tester, 'Plan');
      expect(timer.inProgress, isTrue);
      expect(timer.phase, FocusPhase.focus);
      timer.reset();
    });
  });

  group('real sessions show real data or say there is none', () {
    testWidgets('Plan has no sample schedule, only the empty state', (
      tester,
    ) async {
      await startApp(tester, backend());
      await openTab(tester, 'Plan');
      expect(find.byType(PlanPage), findsOneWidget);
      expect(find.text('No plan yet.'), findsOneWidget);
      expect(find.byType(TimelineRow), findsNothing);
      expect(find.textContaining('SAMPLE'), findsNothing);
      expect(find.text('Thursday, September 24'), findsOneWidget);
    });

    testWidgets('Insights invents nothing', (tester) async {
      await startApp(tester, backend());
      await openTab(tester, 'Insights');
      expect(find.text('No insights yet'), findsOneWidget);
      expect(find.textContaining('SAMPLE'), findsNothing);
    });

    testWidgets('Goals start empty and say they are not synced', (
      tester,
    ) async {
      await startApp(tester, backend());
      await openTab(tester, 'Areas');
      expect(find.text('0 active'), findsOneWidget);
      await tapCard(tester, 'Goals', page: AreasPage);
      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.text('Finish DBMS chapters'), findsNothing);
      expect(find.textContaining('aren’t synced'), findsOneWidget);
    });

    testWidgets('Study shows the real exam and no demo revision', (
      tester,
    ) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Biology',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      await tapCard(tester, 'Study');
      expect(find.byType(StudyPage), findsOneWidget);
      expect(find.text('Unit test'), findsOneWidget, reason: 'the exam');
      expect(find.text('IN 8 DAYS'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget, reason: 'its subject');
      expect(find.text('DBMS Revision'), findsNothing);
      expect(find.text('SAMPLE'), findsNothing);
    });

    testWidgets('Study with no exam says so', (tester) async {
      await startApp(tester, backend());
      await tapCard(tester, 'Study');
      expect(find.text('No exams yet.'), findsOneWidget);
      expect(find.text('No subjects yet.'), findsOneWidget);
    });

    testWidgets('Today with an exam offers Study, never a sample "Why?"', (
      tester,
    ) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Biology',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      expect(find.text('Why?'), findsNothing);
      expect(find.text("View today's plan"), findsNothing);
      await tester.tap(find.text('Open Study'));
      await tester.pumpAndSettle();
      expect(find.byType(StudyPage), findsOneWidget);
    });
  });

  group('known choices are picked, not typed', () {
    testWidgets('sleep quality is chosen from a list and saved', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Sleep');
      await tester.enterText(find.widgetWithText(TextFormField, 'Hours'), '7');
      await pick(tester, 'How did you sleep?', '5 · Great');
      expect(find.text('5 · Great'), findsOneWidget);
      await save(tester);
      final (path, body) = lastPut(server);
      expect(path, '/sleep/$today');
      expect(body['quality'], 5);
    });

    testWidgets('a picker field announces its label, value and action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await startApp(tester, backend());
      await tapCard(tester, 'Sleep');
      final field = find.widgetWithText(PickerField, 'How did you sleep?');
      expect(
        tester.getSemantics(field),
        isSemantics(
          label: 'How did you sleep?',
          value: 'Not rated',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the time zone list can be searched', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile & daily targets'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);

      final zone = find.widgetWithText(PickerField, 'Time zone');
      await tester.ensureVisible(zone);
      await tester.pumpAndSettle();
      await tester.tap(zone);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'toky');
      await tester.pumpAndSettle();
      expect(find.text('Europe/London'), findsNothing);
      await tester.tap(find.text('Asia/Tokyo').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(server.profilePatches.last, {'timezone': 'Asia/Tokyo'});
    });

    testWidgets('preferred workout time is a choice', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile & daily targets'));
      await tester.pumpAndSettle();
      await pick(tester, 'Preferred workout time', 'Morning');
      await save(tester);
      expect(server.profilePatches.last, {'preferred_workout_time': 'morning'});
    });
  });

  for (final dark in [false, true]) {
    testWidgets('Areas, Study and the task form fit 200% text on a 360px phone '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await startApp(tester, backend(), size: const Size(360, 800));
      if (dark) {
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await reveal(tester, SettingsPage, find.text('Dark'));
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      Future<void> scrollThrough() async {
        for (var i = 0; i < 8; i++) {
          await tester.drag(
            find.byType(Scrollable).hitTestable().first,
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }

      await openTab(tester, 'Areas');
      await scrollThrough();
      await tester.drag(
        find.byType(Scrollable).hitTestable().first,
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(StudyPage), findsOneWidget);
      await scrollThrough();
      await openTab(tester, 'Today');
      await tapCard(tester, 'Tasks');
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      await pick(tester, 'Estimated time', 'Custom');
      await scrollThrough();
      expect(tester.takeException(), isNull);
    });
  }
}
