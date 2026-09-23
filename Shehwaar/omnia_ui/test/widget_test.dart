import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/plan/widgets/timeline_row.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/track/track_page.dart';

Future<void> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const OmniaApp());
}

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(find.text(text));
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> selectTheme(WidgetTester tester, String mode) async {
  await tester.scrollUntilVisible(find.byTooltip('Settings'), -200);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tapText(tester, mode);
  final context = tester.element(find.byType(SettingsPage));
  expect(
    Theme.of(context).brightness,
    mode == 'Dark' ? Brightness.dark : Brightness.light,
  );
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
}

void expectTheme(WidgetTester tester, Type page, Brightness brightness) {
  final context = tester.element(find.byType(page));
  expect(Theme.of(context).brightness, brightness);
  expect(
    Theme.of(context).scaffoldBackgroundColor,
    brightness == Brightness.dark ? night : paper,
  );
  for (final element in find.byType(HardCard).evaluate()) {
    final card = element.widget as HardCard;
    final material = tester.widget<Material>(
      find
          .descendant(of: find.byWidget(card), matching: find.byType(Material))
          .first,
    );
    expect(material.color, element.cardColor(card.color));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'All screens and revision tasks work in ${brightness.name} mode',
      (tester) async {
        await startApp(tester);
        await selectTheme(
          tester,
          brightness == Brightness.dark ? 'Dark' : 'Light',
        );
        expectTheme(tester, HomePage, brightness);

        await tapText(tester, "View today's plan");
        expectTheme(tester, PlanPage, brightness);
        await tapText(tester, 'DBMS Revision');
        expectTheme(tester, RevisionDetailPage, brightness);

        await tester.scrollUntilVisible(find.text('Revise normalization'), 180);
        await tapText(tester, 'Revise normalization');
        expect(find.text('Sub-tasks  1/3'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isTrue,
        );
        await tapText(tester, 'Revise normalization');
        expect(find.text('Sub-tasks  0/3'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Mark done'), -180);
        await tapText(tester, 'Mark done');
        await tester.scrollUntilVisible(find.text('Sub-tasks  3/3'), 180);
        expect(find.text('Sub-tasks  3/3'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapText(tester, 'DBMS Revision');
        await tester.scrollUntilVisible(find.text('Sub-tasks  3/3'), 180);
        expect(find.text('Sub-tasks  3/3'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tab(tester, Icons.bar_chart_rounded);
        expectTheme(tester, TrackPage, brightness);
        expect(find.text('4 of 6'), findsOneWidget);
        await tab(tester, Icons.pie_chart_outline);
        expectTheme(tester, InsightsPage, brightness);
        await tab(tester, Icons.home_rounded);
        // Switch back immediately, then verify the retained Plan page follows it.
        await selectTheme(
          tester,
          brightness == Brightness.dark ? 'Light' : 'Dark',
        );
        final opposite = brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
        expectTheme(tester, HomePage, opposite);
        await tab(tester, Icons.calendar_month_outlined);
        expectTheme(tester, PlanPage, opposite);
      },
    );
  }

  testWidgets('Plan views, Home links, and honest placeholder responses work', (
    tester,
  ) async {
    await startApp(tester);
    await tapText(tester, 'Study');
    expect(find.byType(TrackPage), findsOneWidget);
    await tab(tester, Icons.home_rounded);
    await tapText(tester, 'Why?');
    expect(find.text('Sample recommendation'), findsOneWidget);
    await tapText(tester, 'Close');
    await tapText(tester, "View today's plan");
    await tapText(tester, 'List');
    expect(
      tester.widget<TimelineRow>(find.byType(TimelineRow).first).showTimeline,
      isFalse,
    );
    await tapText(tester, 'Morning Routine');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Editing and scheduling'), findsOneWidget);
    await tapText(tester, 'Close');
    await tapText(tester, 'Focus');
    expect(find.byType(TimelineRow), findsNothing);
    await tapText(tester, 'Open revision');
    await tester.scrollUntilVisible(find.text('Start Focus Session'), 200);
    await tapText(tester, 'Start Focus Session');
    expect(find.text('Focus sessions'), findsOneWidget);
    await tapText(tester, 'Close');
    await tester.scrollUntilVisible(
      find.text('DBMS Notes.pdf  ·  Sample'),
      -150,
    );
    await tapText(tester, 'DBMS Notes.pdf  ·  Sample');
    expect(find.text('Sample material'), findsOneWidget);
    await tapText(tester, 'Close');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Timeline');
    expect(
      tester.widget<TimelineRow>(find.byType(TimelineRow).first).showTimeline,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Your plan will adapt as your day changes.'),
      200,
    );
    await tapText(tester, 'Your plan will adapt as your day changes.');
    expect(find.text('Adaptive planning'), findsOneWidget);
    await tapText(tester, 'Close');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Revision edits validate, propagate, and More resets completion',
    (tester) async {
      await startApp(tester);
      await tapText(tester, "View today's plan");
      await tapText(tester, 'DBMS Revision');
      await tapText(tester, 'Edit');
      await tester.enterText(find.byType(TextFormField), ' ');
      await tapText(tester, 'Save');
      expect(find.text('Enter a title'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'SQL practice');
      await tapText(tester, 'Save');
      expect(find.text('SQL practice'), findsNWidgets(2));
      await tapText(tester, 'Mark done');
      await tapText(tester, 'More');
      await tapText(tester, 'Reset sub-tasks');
      await tester.scrollUntilVisible(find.text('Sub-tasks  0/3'), 180);
      expect(find.text('Sub-tasks  0/3'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('SQL practice'), findsOneWidget);
      await tab(tester, Icons.home_rounded);
      await tester.scrollUntilVisible(find.text('SQL practice'), 180);
      await tapText(tester, 'SQL practice');
      expect(find.byType(RevisionDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
