import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';
import 'package:omnia_ui/features/insights/activity_insights.dart';
import 'package:omnia_ui/features/track/data/api_track_repository.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com';

/// The fake dashboard's day: Thursday, September 24 2026.
final thursday = DateTime(2026, 9, 24);

ActivityHistory history(Map<int, ActivityDay> byDay, {int goal = 8000}) =>
    ActivityHistory(
      from: DateTime(2026, 9, 1),
      to: thursday,
      stepGoal: goal,
      logged: byDay.values,
    );

ActivityDay logged(int day, {int steps = 0, int? workout}) => ActivityDay(
  day: DateTime(2026, 9, day),
  steps: steps,
  workoutDone: workout != null,
  workoutMinutes: workout ?? 0,
);

ActivityInsights week(Map<int, ActivityDay> byDay, {int goal = 8000}) {
  final span = insightSpan(InsightRange.week, thursday);
  return ActivityInsights.from(
    history(byDay, goal: goal),
    from: span.from,
    to: span.to,
    today: thursday,
  );
}

Future<FakeAuthBackend> openInsights(
  WidgetTester tester, {
  void Function(FakeAuthBackend)? seed,
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = FakeAuthBackend()
    ..addUser('Sam', sam, 'password-123', signedIn: true);
  seed?.call(backend);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Insights').last);
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  group('spans', () {
    test('a week runs Monday to Sunday around today', () {
      final span = insightSpan(InsightRange.week, thursday);
      expect(span.from, DateTime(2026, 9, 21));
      expect(span.to, DateTime(2026, 9, 27));
    });

    test('a month is the whole calendar month', () {
      final span = insightSpan(InsightRange.month, thursday);
      expect(span.from, DateTime(2026, 9, 1));
      expect(span.to, DateTime(2026, 9, 30));
      final february = insightSpan(InsightRange.month, DateTime(2028, 2, 10));
      expect(february.to, DateTime(2028, 2, 29));
    });
  });

  group('figures come only from logged days', () {
    test('unlogged days are counted apart, never as zero', () {
      final insights = week({
        21: logged(21, steps: 9000, workout: 40),
        23: logged(23, steps: 3000),
      });
      expect(insights.elapsedDays, 4); // Mon–Thu
      expect(insights.loggedDays, 2);
      expect(insights.notLoggedDays, 2);
      expect(insights.workoutDays, 1);
      expect(insights.workoutMinutes, 40);
      expect(insights.averageSteps, 6000); // not (9000 + 3000) / 4
      expect(insights.daysAtStepGoal, 1);
      // Two logged days are too few to call a rate.
      expect(insights.enoughForRates, isFalse);
      expect(insights.workoutRate, isNull);
    });

    test('a logged zero is still data', () {
      final insights = week({21: logged(21), 22: logged(22), 23: logged(23)});
      expect(insights.hasData, isTrue);
      expect(insights.averageSteps, 0);
      expect(insights.workoutRate, 0);
      expect(insights.workoutState(insights.days[0]), DayState.logged);
      expect(insights.stepState(insights.days[0]), DayState.logged);
    });

    test('day states separate hit, logged, not logged and upcoming', () {
      final insights = week({
        21: logged(21, steps: 8000, workout: 30),
        22: logged(22, steps: 7999),
      });
      final [mon, tue, wed, thu, fri, ..._] = insights.days;
      expect(insights.workoutState(mon), DayState.hit);
      expect(insights.stepState(mon), DayState.hit);
      expect(insights.workoutState(tue), DayState.logged);
      expect(insights.stepState(tue), DayState.logged);
      expect(insights.workoutState(wed), DayState.notLogged);
      expect(insights.stepState(thu), DayState.notLogged);
      expect(insights.workoutState(fri), DayState.upcoming);
      expect(insights.days, hasLength(7));
    });

    test('nothing logged means no figures at all', () {
      final insights = week({});
      expect(insights.hasData, isFalse);
      expect(insights.averageSteps, isNull);
      expect(insights.workoutRate, isNull);
    });

    test('no step goal means no goal days', () {
      final insights = week({21: logged(21, steps: 20000)}, goal: 0);
      expect(insights.daysAtStepGoal, 0);
      expect(insights.stepState(insights.days[0]), DayState.logged);
    });
  });

  test(
    'the API drops never-logged placeholders instead of zero-filling',
    () async {
      late Uri url;
      final api = ApiClient(
        baseUrl: 'http://test/api',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'start': '2026-09-21',
              'end': '2026-09-22',
              'step_goal': 9000,
              'days': [
                {
                  'id': 'a1',
                  'day': '2026-09-21',
                  'steps': 0,
                  'workout_done': false,
                  'workout_minutes': 0,
                  'workout_type': null,
                },
                {
                  'id': null,
                  'day': '2026-09-22',
                  'steps': 0,
                  'workout_done': false,
                  'workout_minutes': 0,
                  'workout_type': null,
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final history = await ApiTrackRepository(api)
          .activityHistory(DateTime(2026, 9, 21), DateTime(2026, 9, 22));
      expect(url.path, '/api/activity');
      expect(url.queryParameters, {'from': '2026-09-21', 'to': '2026-09-22'});
      expect(history.stepGoal, 9000);
      expect(history.on(DateTime(2026, 9, 21))?.steps, 0); // a logged zero
      expect(history.on(DateTime(2026, 9, 22)), isNull); // never logged
    },
  );

  group('Insights tab', () {
    testWidgets('shows real weekly figures and a habit grid', (tester) async {
      final backend = await openInsights(
        tester,
        size: const Size(430, 2000),
        seed: (backend) => backend
          ..logActivity(sam, '2026-09-21', steps: 9100, workoutMinutes: 45)
          ..logActivity(sam, '2026-09-22', steps: 4000)
          ..logActivity(sam, '2026-09-23', steps: 8200, workoutMinutes: 30),
      );
      expect(backend.activityRanges, ['2026-09-21..2026-09-24']);
      expect(find.text('THIS WEEK  ·  Sep 21 – Sep 27'), findsOneWidget);
      expect(find.text('2 workouts in 3 days logged'), findsOneWidget);
      expect(find.textContaining('1h 15m in total'), findsOneWidget);
      expect(find.textContaining('67% of logged days'), findsOneWidget);
      expect(find.text('7,100 a day on average'), findsOneWidget);
      expect(find.text('2 of 3 days logged reached 8,000.'), findsOneWidget);
      expect(find.textContaining('1 day not logged'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Monday, September 21: workout, 45 minutes'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Thursday, September 24: not logged'),
        findsNWidgets(2),
      );
      expect(find.textContaining('SAMPLE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month view requests the month up to today', (
      tester,
    ) async {
      final backend = await openInsights(
        tester,
        size: const Size(430, 2000),
        seed: (backend) =>
            backend
              ..logActivity(sam, '2026-09-02', steps: 100, workoutMinutes: 20),
      );
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(backend.activityRanges.last, '2026-09-01..2026-09-24');
      expect(find.text('THIS MONTH  ·  SEP 2026'), findsOneWidget);
      expect(find.text('1 workout in 1 day logged'), findsOneWidget);
      expect(
        find.textContaining('Log at least $minDaysForRates days'),
        findsOneWidget,
      );
      expect(find.textContaining('23 days not logged'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final backend = await openInsights(
        tester,
        size: const Size(430, 2000),
        seed: (backend) => backend.trackDown = true,
      );
      expect(find.text("Couldn't load insights"), findsOneWidget);
      backend.trackDown = false;
      backend.logActivity(sam, '2026-09-24', steps: 500);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('0 workouts in 1 day logged'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits a narrow phone at 200% text ($brightness)', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await openInsights(
          tester,
          size: const Size(320, 640),
          seed: (backend) => backend
            ..logActivity(sam, '2026-09-21', steps: 9100, workoutMinutes: 45)
            ..logActivity(sam, '2026-09-22', steps: 300),
        );
        ThemeScope.of(tester.element(find.text('Insights').first))
            .value = brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          Theme.of(tester.element(find.text('Insights').first)).brightness,
          brightness,
        );
        for (final text in ['Workouts'.toUpperCase(), 'Steps'.toUpperCase()]) {
          await tester.scrollUntilVisible(
            find.text(text),
            200,
            scrollable: find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
