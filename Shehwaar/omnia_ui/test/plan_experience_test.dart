import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_preferences_page.dart';
import 'package:omnia_ui/features/plan/plan_time.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';
import 'package:omnia_ui/features/plan/widgets/plan_date_strip.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';
import 'package:omnia_ui/features/tasks/task_form_page.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

import 'plan_api_test.dart' show payload;
import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com';
Map<String, dynamic> suggestion(String day) => {
  ...payload,
  'plan_date': day,
  'source': 'ollama',
  'is_fallback': false,
  'planning_start_minutes': 480,
  'planning_end_minutes': 1320,
};

void main() {
  test(
    'time preference changes only presentation including midnight and noon',
    () {
      expect(formatPlanTime('00:05', '12h'), '12:05 AM');
      expect(formatPlanTime('12:00', '12h'), '12:00 PM');
      expect(formatPlanTime('18:00', '12h'), '6:00 PM');
      expect(formatPlanTime('18:00', '24h'), '18:00');
    },
  );

  test(
    'date selection discards late responses and keeps empty dates empty',
    () async {
      final repo = DatedRepository();
      final controller = PlanController(repo);
      final first = controller.load();
      final second = controller.selectDate(DateTime(2026, 9, 26));
      repo.requests[1].complete(null);
      await second;
      repo.requests[0].complete(DailyPlan.fromJson(payload));
      await first;
      expect(controller.plan, isNull);
      expect(controller.selectedDate, DateTime(2026, 9, 26));
      expect(repo.dates, [null, DateTime(2026, 9, 26)]);
      controller.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'date strip scrolls and selects at 200% on narrow $brightness phone',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        DateTime? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: PlanDateStrip(
                  today: DateTime(2026, 9, 28),
                  selected: DateTime(2026, 9, 28),
                  onSelect: (day) => selected = day,
                ),
              ),
            ),
          ),
        );
        await tester.drag(
          find.byKey(const ValueKey('plan-date-strip')),
          const Offset(-210, 0),
        );
        await tester.pumpAndSettle();
        final strip = find.byType(PlanDateStrip);
        final numbers = find
            .descendant(of: strip, matching: find.text('1'))
            .hitTestable();
        if (numbers.evaluate().isNotEmpty) await tester.tap(numbers.first);
        await tester.tap(
          find.descendant(
            of: find.byType(PlanDateStrip),
            matching: find.text('Today'),
          ),
        );
        expect(selected, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'OmniAI summary discloses details, date retrieval, empty date, Today and Focus',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.dashboardDate = '2026-09-27';
      backend.plans[sam] = suggestion('2026-09-27');
      final api = backend.client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      expect(find.text('OMNIAI PLAN'), findsOneWidget);
      expect(find.textContaining('Not accepted'), findsNothing);
      await tester.tap(find.text('Why?'));
      await tester.pumpAndSettle();
      expect(find.text('Why this plan?'), findsOneWidget);
      expect(
        find.text(
          'This saved suggestion arranges work within its planning window.',
        ),
        findsOneWidget,
        reason: 'older persisted plans have no typed explanation',
      );
      await tester.ensureVisible(find.text('Show details'));
      await tester.tap(find.text('Show details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('not accepted'),
        140,
        scrollable: find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('not accepted'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      backend.plans[sam] = {
        ...suggestion('2026-09-28'),
        'summary': 'Different saved day',
      };
      await tester.tap(
        find
            .descendant(
              of: find.byType(PlanDateStrip),
              matching: find.text('28'),
            )
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Different saved day'), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(PlanDateStrip),
              matching: find.text('29'),
            )
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('No plan for this date.'), findsOneWidget);
      expect(find.text('Generate suggestion'), findsNothing);
      backend.plans[sam] = suggestion('2026-09-27');
      await tester.tap(
        find.descendant(
          of: find.byType(PlanDateStrip),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('OMNIAI PLAN'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open Focus Timer'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(DailyPlanView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find
            .descendant(
              of: find.byType(DailyPlanView),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Focus Timer'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusTimerPage), findsOneWidget);
    },
  );

  for (final source in ['ollama', 'rules', 'fallback']) {
    testWidgets('$source plan explanation is concise before Show details', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.profileOf(sam)!['time_format'] = '12h';
      backend.plans[sam] = {
        ...suggestion(backend.dashboardDate),
        'source': source == 'fallback' ? 'rules' : source,
        'is_fallback': source == 'fallback',
        'explanation': {
          'headline': 'Nearby deadlines shape this day.',
          'key_reasons': [
            'One task has reserved time.',
            'DBMS revision has a place.',
          ],
          'supporting_context': ['Sleep was shorter last night.'],
        },
        'assumptions': ['Calendar availability is not connected.'],
        'adjustments': ['A longer secondary explanation.'],
      };
      final api = backend.client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      expect(find.text('Nearby deadlines shape this day.'), findsOneWidget);
      expect(find.text('Assignment first.'), findsNothing);
      await tester.tap(find.text('Why?'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.text('Nearby deadlines shape this day.'),
        ),
        findsOneWidget,
      );
      expect(find.text('One task has reserved time.'), findsOneWidget);
      expect(find.text('DBMS revision has a place.'), findsOneWidget);
      expect(
        find.text('Calendar availability is not connected.'),
        findsNothing,
      );
      expect(find.textContaining('not accepted'), findsNothing);
      await tester.ensureVisible(find.text('Show details'));
      await tester.tap(find.text('Show details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Calendar availability is not connected.'),
        140,
        scrollable: find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Calendar availability is not connected.'),
        findsOneWidget,
      );
      final window = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.textContaining('7:00 PM'),
      );
      await tester.scrollUntilVisible(
        window,
        140,
        scrollable: find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(window, findsOneWidget);
      expect(
        find.textContaining(source == 'ollama' ? 'OmniAI' : 'Rules'),
        findsWidgets,
      );
    });
  }

  testWidgets(
    'task block edits the canonical task without rewriting plan times',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      final id = backend.addTask(sam, 'Real assignment');
      final data = suggestion(backend.dashboardDate);
      data['items'] = [
        {
          ...(payload['items'] as List).first as Map<String, Object?>,
          'task_id': id,
        },
      ];
      backend.plans[sam] = data;
      final api = backend.client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assignment'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormPage), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Real assignment'),
        'Edited assignment',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('No estimate'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(TaskFormPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('No estimate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1h').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(TaskFormPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(backend.tasksOf(sam).single['title'], 'Edited assignment');
      expect(backend.tasksOf(sam).single['estimated_minutes'], 60);
      final plan = PlanScope.of(tester.element(find.byType(DailyPlanView)));
      expect(plan.plan!.items.single.end, '19:55');
      expect(plan.plan!.items.single.title, 'Assignment');
      expect(plan.mayBeStale, isTrue);
      expect(
        backend.requests.where((r) => r == 'POST /ai/daily-plan'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'preference form saves and restores per account without regenerating',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true)
        ..addUser('Ada', 'ada@example.com', 'password-456');
      final api = backend.client();
      addTearDown(api.close);
      final auth = AuthController(api);
      addTearDown(auth.dispose);
      await auth.restore();
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PlanPreferencesPage(),
                    ),
                  ),
                  child: const Text('Preferences'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      expect(find.text('08:00'), findsOneWidget);
      for (final entry in [('Start time', '10'), ('End time', '20')]) {
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Switch to text input mode'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, entry.$2);
        await tester.enterText(find.byType(TextField).last, '00');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('12-hour'));
      await tester.pumpAndSettle();
      expect(find.text('10:00 AM'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(auth.user!.profile.timeFormat, '12h');
      expect(auth.user!.profile.planningStartMinutes, 600);
      expect(auth.user!.profile.planningEndMinutes, 1200);
      await auth.restore();
      expect(auth.user!.profile.timeFormat, '12h');
      expect(
        backend.requests.where((r) => r == 'POST /ai/daily-plan'),
        isEmpty,
      );
      await auth.signOut();
      await auth.signIn('ada@example.com', 'password-456');
      expect(auth.user!.profile.timeFormat, '24h');
    },
  );
}

class DatedRepository implements PlanRepository {
  final dates = <DateTime?>[];
  final requests = <Completer<DailyPlan?>>[];
  @override
  Future<DailyPlan?> getToday({DateTime? date}) {
    dates.add(date);
    final request = Completer<DailyPlan?>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<DailyPlan> generate() => throw UnimplementedError();
}
