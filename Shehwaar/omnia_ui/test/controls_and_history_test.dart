import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/widgets/number_wheel.dart';
import 'package:omnia_ui/core/widgets/omnia_icon_button.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/study/domain/study_log.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com';

Future<FakeAuthBackend> start(
  WidgetTester tester, {
  FakeAuthBackend? backend,
  FocusTimerController? timer,
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server =
      backend ??
      (FakeAuthBackend()..addUser('Sam', sam, 'password-123', signedIn: true));
  final api = server.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api, focusTimer: timer));
  await tester.pumpAndSettle();
  return server;
}

ButtonStyle? settingsStyle(WidgetTester tester) => tester
    .widget<IconButton>(
      find.descendant(
        of: find.byType(OmniaIconButton),
        matching: find.byType(IconButton),
      ),
    )
    .style;

void main() {
  group('Settings button', () {
    for (final brightness in Brightness.values) {
      testWidgets('is a bordered, shadowed card square ($brightness)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: OmniaIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(OmniaIconButton));
        final style = settingsStyle(tester)!;
        final fill = style.backgroundColor!.resolve({})!;
        expect(fill, brightness == Brightness.dark ? sleepDark : lilac);
        final shape = style.shape!.resolve({})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
        expect(shape.side.width, 1.6);
        expect(shape.side.color, SurfaceStyle.of(context).outlineOn(fill));
        // Ink on the pastel fill in both themes: high contrast.
        expect(style.foregroundColor!.resolve({}), ink);
        expect(
          tester
              .widget<OmniaPressable>(find.byType(OmniaPressable))
              .shadowOffset,
          const Offset(2, 3),
        );
        expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(IconButton)),
          isSemantics(
            tooltip: 'Settings',
            isButton: true,
            hasTapAction: true,
          ),
        );
      });
    }

    testWidgets('opens Settings from Today', (tester) async {
      await start(tester);
      expect(find.byType(OmniaIconButton), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });

  group('NumberWheel', () {
    testWidgets('a drag picks a neighbouring value and keeps it visible', (
      tester,
    ) async {
      var value = 7;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => NumberWheel(
                  label: 'Hours',
                  values: [for (var h = 0; h <= 24; h++) h],
                  value: value,
                  format: (h) => '$h h',
                  onChanged: (h) => setState(() => value = h),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('7 h'), findsOneWidget);
      final item = tester.getSize(find.text('7 h')).height;
      await tester.drag(find.text('7 h'), Offset(0, -item * 2.2));
      await tester.pumpAndSettle();
      expect(value, greaterThan(7));
      expect(find.text('$value h'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Hours')), findsWidgets);
    });

    testWidgets('fits a narrow phone at 200% text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Wrap(
              children: [
                NumberWheel(
                  label: 'Minutes',
                  values: [for (var m = 0; m < 60; m++) m],
                  value: 59,
                  format: (m) => '$m min',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('59 min'), findsOneWidget);
    });
  });

  group('study history and insights', () {
    testWidgets('Focus time is sent with its start, listed and charted', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 9, 24, 9, 30);
      final timer = FocusTimerController(now: () => now);
      addTearDown(timer.dispose);
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      await start(
        tester,
        backend: backend,
        timer: timer,
        size: const Size(430, 1600),
      );
      timer.start();
      now = now.add(timer.phaseDuration);
      timer.tick();
      await tester.pumpAndSettle();

      final (_, body) = backend.studyWrites.last;
      expect(body['source'], 'focus');
      expect(body['duration_minutes'], 25);
      expect(
        DateTime.parse(body['started_at'] as String),
        DateTime.utc(2026, 9, 24, 9, 30),
      );

      // Study lists it as Focus time.
      await tester.tap(find.text('Areas').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Recent study'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Focus'), findsWidgets);
      expect(find.text('25m'), findsOneWidget);

      // Insights counts it in the Study card.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insights').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('25m studied'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      expect(find.text('25m studied'), findsOneWidget);
      expect(find.textContaining('25m from Focus'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Thursday, September 24: 25m studied'),
        findsOneWidget,
      );
    });

    test('study log maps each source', () {
      Map<String, dynamic> row(String? source) => {
        'id': 's',
        'session_date': '2026-09-24',
        'duration_minutes': 30,
        'source': source,
        'subject': {'id': 'x', 'name': 'DBMS', 'color': null},
      };
      expect(studyLogFromApi(row('plan')).source, StudySource.plan);
      expect(studyLogFromApi(row('focus')).source, StudySource.focus);
      expect(studyLogFromApi(row(null)).source, StudySource.manual);
      final log = studyLogFromApi(jsonDecode(jsonEncode(row('plan'))));
      expect(log.subjectName, 'DBMS');
      expect(log.day, DateTime(2026, 9, 24));
    });
  });

  testWidgets('Home keeps its layout with the new Settings button', (
    tester,
  ) async {
    await start(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
