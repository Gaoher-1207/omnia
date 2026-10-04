import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';

const _planJson = {
  'id': 'plan-1',
  'revision': 4,
  'plan_date': '2026-09-27',
  'created_at': '2026-09-27T19:00:00Z',
  'source': 'rules',
  'is_fallback': true,
  'summary': 'Assignment first.',
  'items': [
    {
      'item_key': 'task-key',
      'start': '19:00',
      'end': '19:55',
      'category': 'task',
      'title': 'Assignment',
      'task_id': 'task-1',
    },
  ],
};

const _proposalJson = {
  'id': 'proposal-1',
  'base_plan_id': 'plan-1',
  'base_revision': 4,
  'plan_date': '2026-09-27',
  'status': 'pending',
  'request': 'Move assignment later',
  'summary': 'Assignment moved to a later slot.',
  'explanation': 'An open slot is available after dinner.',
  'operations': [
    {
      'kind': 'MOVE',
      'item_key': 'task-key',
      'entity_id': 'task-1',
      'before': {'start': '19:00'},
      'after': {'start': '20:00'},
      'reason': 'The later slot is free.',
    },
  ],
  'schedule': [
    {
      'item_key': 'task-key',
      'start': '20:00',
      'end': '20:55',
      'category': 'task',
      'title': 'Assignment',
      'task_id': 'task-1',
    },
  ],
  'warnings': ['Review the remaining study time.'],
  'validation': {'valid': true, 'applicable': true},
  'created_at': '2026-09-27T19:00:00Z',
  'expires_at': '2026-09-27T19:30:00Z',
};

void main() {
  test('proposal creation reloads persisted proposal for preview', () async {
    final repository = _ReplanRepository();
    final controller = PlanController(repository);
    expect(
      await controller.createReplanProposal('Move assignment later'),
      isTrue,
    );
    expect(repository.createCalls, 1);
    expect(repository.getProposalCalls, 1);
    expect(repository.lastRequest, 'Move assignment later');
    expect(controller.replanProposal?.summary, contains('later slot'));
    controller.dispose();
  });

  test('approval applies once and refreshes displayed plan revision', () async {
    final repository = _ReplanRepository()..appliedPlan = _newPlan(5);
    final controller = _readyController(repository);
    await controller.createReplanProposal('Move assignment later');
    expect(await controller.applyReplanProposal(), isTrue);
    expect(await controller.applyReplanProposal(), isFalse);
    expect(repository.applyCalls, 1);
    expect(repository.readCalls, 1);
    expect(controller.plan?.revision, 5);
    expect(controller.todayPlan?.revision, 5);
    expect(controller.replanNotice, 'Plan updated · Revision 5');
    controller.dispose();
  });

  test('dismissal calls backend and clears pending preview', () async {
    final repository = _ReplanRepository();
    final controller = _readyController(repository);
    await controller.createReplanProposal('Move assignment later');
    expect(await controller.dismissReplanProposal(), isTrue);
    expect(repository.dismissCalls, 1);
    expect(controller.replanProposal, isNull);
    controller.dispose();
  });

  test(
    'stale proposal refreshes plan and exposes user-facing notice',
    () async {
      final repository = _ReplanRepository()
        ..applyFailure = const ApiException(
          statusCode: 409,
          code: 'replan_proposal_stale',
          message: 'Stale proposal',
        )
        ..currentPlan = _newPlan(6);
      final controller = _readyController(repository);
      await controller.createReplanProposal('Move assignment later');
      expect(await controller.applyReplanProposal(), isFalse);
      expect(repository.readCalls, 1);
      expect(controller.replanProposal, isNull);
      expect(controller.plan?.revision, 6);
      expect(controller.replanNotice, contains('plan changed'));
      controller.dispose();
    },
  );

  test(
    'provider/API errors are surfaced and proposal actions unlock',
    () async {
      final repository = _ReplanRepository()
        ..createFailure = const ApiException(
          statusCode: 503,
          code: 'provider_unavailable',
          message: 'Planner unavailable',
        );
      final controller = PlanController(repository);
      expect(
        await controller.createReplanProposal('Move assignment later'),
        isFalse,
      );
      expect(controller.replanError, isA<ApiException>());
      expect(controller.creatingProposal, isFalse);
      controller.dispose();
    },
  );

  testWidgets('preview shows proposal details and approve refreshes revision', (
    tester,
  ) async {
    final repository = _ReplanRepository()..appliedPlan = _newPlan(5);
    final controller = _readyController(repository);
    final focus = FocusTimerController();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      PlanScope(
        controller: controller,
        child: FocusTimerScope(
          controller: focus,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(body: DailyPlanView(today: DateTime(2026, 9, 27))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust today’s plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Move assignment later');
    await tester.tap(find.text('Preview changes'));
    await tester.pumpAndSettle();
    expect(find.text('Assignment moved to a later slot.'), findsOneWidget);
    expect(
      find.text('An open slot is available after dinner.'),
      findsOneWidget,
    );
    expect(find.text('The later slot is free.'), findsOneWidget);
    expect(find.text('20:00–20:55'), findsOneWidget);
    expect(find.text('Review the remaining study time.'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(repository.applyCalls, 1);
    expect(find.text('Revision 5'), findsOneWidget);
    expect(find.text('Plan updated · Revision 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

PlanController _readyController(_ReplanRepository repository) {
  final controller = PlanController(repository);
  controller.seedToday(DateTime(2026, 9, 27), DailyPlan.fromJson(_planJson));
  return controller;
}

DailyPlan _newPlan(int revision) => DailyPlan.fromJson({
  ..._planJson,
  'revision': revision,
  'created_at': '2026-09-27T20:00:00Z',
});

class _ReplanRepository implements PlanRepository {
  DailyPlan currentPlan = DailyPlan.fromJson(_planJson);
  DailyPlan? appliedPlan;
  Object? createFailure, applyFailure;
  int createCalls = 0, getProposalCalls = 0, applyCalls = 0, dismissCalls = 0;
  int readCalls = 0;
  String? lastRequest;

  @override
  Future<DailyPlan?> getToday({DateTime? date}) async {
    readCalls++;
    return currentPlan;
  }

  @override
  Future<DailyPlan> generate() async => currentPlan;

  @override
  Future<ReplanProposal> createReplanProposal(
    String request, {
    DateTime? date,
  }) async {
    createCalls++;
    lastRequest = request;
    if (createFailure case final failure?) throw failure;
    return ReplanProposal.fromJson(_proposalJson);
  }

  @override
  Future<ReplanProposal> getReplanProposal(String proposalId) async {
    getProposalCalls++;
    return ReplanProposal.fromJson(_proposalJson);
  }

  @override
  Future<DailyPlan> applyReplanProposal(String proposalId) async {
    applyCalls++;
    if (applyFailure case final failure?) throw failure;
    currentPlan = appliedPlan ?? _newPlan(5);
    return currentPlan;
  }

  @override
  Future<ReplanProposal> dismissReplanProposal(String proposalId) async {
    dismissCalls++;
    return ReplanProposal.fromJson({..._proposalJson, 'status': 'dismissed'});
  }
}
