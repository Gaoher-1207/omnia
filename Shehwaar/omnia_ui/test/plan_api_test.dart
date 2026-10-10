import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/plan/data/api_plan_repository.dart';
import 'package:omnia_ui/features/plan/data/mock_plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';

import 'support/fake_auth_backend.dart';

const payload = {
  'id': 'plan-1',
  'revision': 2,
  'plan_date': '2026-09-27',
  'created_at': '2026-09-27T19:00:00Z',
  'source': 'rules',
  'is_fallback': true,
  'summary': 'Assignment first.',
  'validation_version': 1,
  'window_start': '19:00',
  'window_end': '22:00',
  'assumptions': ['Assumes free time until 22:00.'],
  'tips': <String>[],
  'adjustments': ['Shorter workout after poor sleep.'],
  'items': [
    {
      'start': '19:00',
      'item_key': 'stable-item-1',
      'end': '19:55',
      'category': 'task',
      'title': 'Assignment',
      'detail': null,
      'task_id': 'task-1',
      'subject_id': null,
    },
  ],
  'unscheduled': [
    {
      'title': 'DBMS revision',
      'category': 'study',
      'remaining_minutes': 60,
      'reason': 'not_scheduled',
      'subject_id': 'subject-1',
      'task_id': null,
    },
  ],
};

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('suggestion fits a narrow phone at 200% text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = PlanController(
        MockPlanRepository(DailyPlan.fromJson(payload)),
      );
      final focus = FocusTimerController();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        PlanScope(
          controller: controller,
          child: FocusTimerScope(
            controller: focus,
            child: MaterialApp(
              theme: buildAppTheme(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const Scaffold(body: DailyPlanView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Why?'), 120);
      await tester.tap(find.text('Why?'));
      await tester.pumpAndSettle();
      expect(find.text('Why this plan?'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Show details'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show details').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Show details'));
      await tester.pumpAndSettle();
      expect(find.text('Hide details'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'explanation sheet');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Generate new suggestion'),
        250,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'signed-in sessions read their own plan and clear it on account change',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', 'sam@example.com', 'password-123', signedIn: true)
        ..addUser('Ada', 'ada@example.com', 'password-456');
      backend.plans['sam@example.com'] = Map<String, dynamic>.from(payload);
      backend.dashboardDate = '2026-09-27';
      final api = backend.client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      final home = tester.element(find.byType(HomePage));
      final auth = AuthScope.of(home);
      final first = PlanScope.of(home);
      expect(first.plan?.id, 'plan-1');
      await auth.signOut();
      await tester.pumpAndSettle();
      await auth.signIn('ada@example.com', 'password-456');
      await tester.pumpAndSettle();
      final second = PlanScope.of(tester.element(find.byType(HomePage)));
      expect(identical(first, second), isFalse);
      expect(second.loaded, isTrue);
      expect(second.plan, isNull);
    },
  );
  test(
    'API reads, maps and explicitly generates; only 404 means no plan',
    () async {
      var status = 404;
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://test/api',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              status == 200
                  ? payload
                  : {
                      'error': {'code': 'error'},
                    },
            ),
            status,
          );
        }),
      );
      addTearDown(api.close);
      await api.setToken('test-token');
      final repository = ApiPlanRepository(api);
      expect(await repository.getToday(), isNull);
      status = 503;
      await expectLater(repository.getToday(), throwsException);
      status = 200;
      final plan = await repository.generate();
      expect(plan.items.single.minutes, 55);
      expect(plan.revision, 2);
      expect(plan.items.single.itemKey, 'stable-item-1');
      expect(plan.unscheduled.single.remainingMinutes, 60);
      expect(plan.isFallback, isTrue);
      expect(requests.last.url.path, '/api/ai/daily-plan');
      expect(requests.last.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(requests.last.body), {'regenerate': true});
      final dated = await repository.getToday(date: DateTime(2026, 9, 27));
      expect(requests.last.url.queryParameters['date'], '2026-09-27');
      expect(dated!.date, DateTime(2026, 9, 27));
    },
  );

  test(
    'replan API keeps proposal preview separate from explicit apply',
    () async {
      final requests = <http.Request>[];
      final proposal = {
        'id': 'proposal-1',
        'base_plan_id': 'plan-1',
        'base_revision': 2,
        'plan_date': '2026-09-27',
        'status': 'pending',
        'request': 'Move my assignment later',
        'summary': 'Assignment moved.',
        'explanation': 'A later open slot is available.',
        'operations': [
          {
            'kind': 'MOVE',
            'item_key': 'stable-item-1',
            'entity_id': 'task-1',
            'before': {'start': '19:00'},
            'after': {'start': '20:00'},
            'reason': 'The later slot is free.',
          },
        ],
        'schedule': [
          {
            'item_key': 'stable-item-1',
            'start': '19:00',
            'end': '19:55',
            'category': 'task',
            'title': 'Assignment',
            'detail': null,
            'task_id': 'task-1',
            'subject_id': null,
          },
        ],
        'warnings': <String>[],
        'validation': {'valid': true, 'applicable': true},
        'created_at': '2026-09-27T19:00:00Z',
        'expires_at': '2026-09-27T19:30:00Z',
        'applied_at': null,
        'dismissed_at': null,
      };
      final api = ApiClient(
        baseUrl: 'http://test/api',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/apply')) {
            return http.Response(jsonEncode(payload), 200);
          }
          return http.Response(jsonEncode(proposal), 201);
        }),
      );
      addTearDown(api.close);
      final repository = ApiPlanRepository(api);

      final preview = await repository.createReplanProposal(
        'Move my assignment later',
        date: DateTime(2026, 9, 27),
      );
      expect(preview.status, 'pending');
      expect(preview.baseRevision, 2);
      expect(preview.operations.single.kind, 'MOVE');
      expect(preview.schedule.single.itemKey, 'stable-item-1');
      expect(requests.single.url.path, '/api/ai/replan/proposals');
      expect(jsonDecode(requests.single.body), {
        'request': 'Move my assignment later',
        'plan_date': '2026-09-27',
      });

      final applied = await repository.applyReplanProposal(preview.id);
      expect(applied.revision, 2);
      expect(
        requests.last.url.path,
        '/api/ai/replan/proposals/proposal-1/apply',
      );
      expect(requests.last.body, isEmpty);

      final reloaded = await repository.getReplanProposal(preview.id);
      expect(reloaded.id, 'proposal-1');
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/api/ai/replan/proposals/proposal-1');

      await repository.dismissReplanProposal(preview.id);
      expect(requests.last.method, 'POST');
      expect(
        requests.last.url.path,
        '/api/ai/replan/proposals/proposal-1/dismiss',
      );
    },
  );

  test('controller serializes operations, preserves failed read state, ignores disposed results', () async {
    final repo = PendingRepository();
    final controller = PlanController(repo);
    final loading = controller.load();
    await controller.generate();
    expect(repo.calls, 1);
    repo.pending.complete(DailyPlan.fromJson(payload));
    await loading;
    expect(controller.plan?.id, 'plan-1');
    repo.pending = Completer<DailyPlan?>();
    final reload = controller.load();
    repo.pending.completeError(Exception('offline'));
    await reload;
    expect(controller.plan?.id, 'plan-1');
    expect(controller.error, isNotNull);
    repo.pending = Completer<DailyPlan?>();
    final last = controller.load();
    controller.dispose();
    repo.pending.complete(null);
    await last;
  });

  testWidgets(
    'real plan shows source, unfinished work and recovery; honest loading and error',
    (tester) async {
      final repo = PendingRepository();
      final controller = PlanController(repo);
      addTearDown(controller.dispose);
      final focus = FocusTimerController();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        PlanScope(
          controller: controller,
          child: FocusTimerScope(
            controller: focus,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const Scaffold(body: DailyPlanView()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      repo.pending = Completer<DailyPlan?>();
      await tester.tap(find.text('Try again'));
      repo.pending.complete(DailyPlan.fromJson(payload));
      await tester.pumpAndSettle();
      expect(find.text('Assignment'), findsOneWidget);
      expect(find.text('Suggested plan'), findsOneWidget);
      expect(find.text('Rules fallback'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('DBMS revision'), 250);
      expect(find.text('DBMS revision'), findsOneWidget);
      expect(find.textContaining('60 min'), findsOneWidget);
    },
  );
}

class PendingRepository implements PlanRepository {
  var pending = Completer<DailyPlan?>();
  int calls = 0;
  @override
  Future<DailyPlan?> getToday({DateTime? date}) {
    calls++;
    return pending.future;
  }

  @override
  Future<DailyPlan> generate() async {
    calls++;
    return (await pending.future)!;
  }

  @override
  Future<Never> createReplanProposal(String request, {DateTime? date}) async =>
      throw StateError('Not used in this test.');
  @override
  Future<Never> getReplanProposal(String proposalId) async =>
      throw StateError('Not used in this test.');
  @override
  Future<Never> applyReplanProposal(String proposalId) async =>
      throw StateError('Not used in this test.');
  @override
  Future<Never> dismissReplanProposal(String proposalId) async =>
      throw StateError('Not used in this test.');
}
