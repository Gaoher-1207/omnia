import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/assistant/assistant_controller.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';
import 'package:omnia_ui/features/assistant/plan_change_offer.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';

const _plan = {
  'id': 'plan-1',
  'revision': 1,
  'plan_date': '2026-09-27',
  'created_at': '2026-09-27T08:00:00Z',
  'source': 'rules',
  'is_fallback': false,
  'summary': 'Plan',
  'items': [
    {
      'item_key': 'gym',
      'start': '16:30',
      'end': '17:30',
      'category': 'fitness',
      'title': 'Gym',
    },
  ],
};

Map<String, dynamic> _proposal(String request) => {
  'id': 'proposal-1',
  'base_plan_id': 'plan-1',
  'base_revision': 1,
  'plan_date': '2026-09-27',
  'status': 'pending',
  'request': request,
  'summary': 'Internal summary',
  'explanation': 'Internal explanation',
  'operations': [
    {
      'kind': 'MOVE',
      'item_key': 'gym',
      'before': {'start': '16:30', 'end': '17:30', 'title': 'Gym'},
      'after': {'start': '19:00', 'end': '20:00', 'title': 'Gym'},
      'reason': 'Free later.',
    },
  ],
  'schedule': <Map<String, dynamic>>[],
  'warnings': <String>[],
  'validation': {'valid': true},
  'created_at': '2026-09-27T08:00:00Z',
  'expires_at': '2026-09-27T08:30:00Z',
};

class _Plans implements PlanRepository {
  @override
  Future<Never> addItem(
    DateTime day,
    ManualPlanItemDraft draft, {
    int? baseRevision,
  }) => throw UnimplementedError();

  @override
  Future<Never> removeItem(DateTime day, String itemKey, {int? baseRevision}) =>
      throw UnimplementedError();

  final requests = <String>[];
  int applied = 0, dismissed = 0;

  @override
  Future<DailyPlan?> getToday({DateTime? date}) async =>
      DailyPlan.fromJson(_plan);
  @override
  Future<DailyPlan> generate() async => DailyPlan.fromJson(_plan);
  @override
  Future<ReplanProposal> createReplanProposal(
    String request, {
    DateTime? date,
  }) async {
    requests.add(request);
    return ReplanProposal.fromJson(_proposal(request));
  }

  @override
  Future<ReplanProposal> getReplanProposal(String proposalId) async =>
      ReplanProposal.fromJson(_proposal(requests.last));
  @override
  Future<DailyPlan> applyReplanProposal(String proposalId) async {
    applied++;
    return DailyPlan.fromJson({..._plan, 'revision': 2});
  }

  @override
  Future<ReplanProposal> dismissReplanProposal(String proposalId) async {
    dismissed++;
    return ReplanProposal.fromJson(_proposal(requests.last));
  }

  @override
  Future<DailyPlan> recordOutcome(
    DateTime day,
    String itemKey,
    String? status, {
    int? minutes,
  }) async => DailyPlan.fromJson(_plan);
}

class _Replies implements AssistantRepository {
  @override
  Future<String> ask(String message, List<AssistantMessage> history) async =>
      'Your gym block is at 4:30 PM.';
}

Future<_Plans> _open(
  WidgetTester tester, {
  bool sample = false,
  bool withPlan = true,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final plans = _Plans();
  final mock = AppDependencies.mock();
  final plan = PlanController(plans);
  if (withPlan) {
    plan.seedToday(DateTime(2026, 9, 27), DailyPlan.fromJson(_plan));
  }
  final assistant = AssistantController(_Replies());
  addTearDown(plan.dispose);
  addTearDown(assistant.dispose);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: AppDependencies(
        tasks: mock.tasks,
        goals: mock.goals,
        study: mock.study,
        dashboard: mock.dashboard,
        track: mock.track,
        revision: mock.revision,
        assistant: mock.assistant,
        initialRevisionSession: mock.initialRevisionSession,
        plan: plans,
        commitments: mock.commitments,
        sampleContent: sample,
      ),
      child: PlanScope(
        controller: plan,
        child: AssistantScope(
          controller: assistant,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const AssistantPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return plans;
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pumpAndSettle();
}

void main() {
  group('looksLikePlanChange', () {
    for (final text in [
      'Move my workout to 7 pm',
      'Skip the gym today',
      'Can you push study later this evening?',
      'Add a 30 minute walk to my plan',
      'Reschedule the assignment block',
    ]) {
      test('yes: $text', () => expect(looksLikePlanChange(text), isTrue));
    }
    for (final text in [
      'What should I prioritize tonight?',
      'How am I doing today?',
      'What exams do I have coming up?',
      'Move',
      'Should I study or work out first?',
    ]) {
      test('no: $text', () => expect(looksLikePlanChange(text), isFalse));
    }
  });

  testWidgets('a change request offers a preview; Apply is still explicit', (
    tester,
  ) async {
    final plans = await _open(tester);
    await _ask(tester, 'Move my gym to 7 pm today');
    expect(find.text('Your gym block is at 4:30 PM.'), findsOneWidget);
    expect(plans.requests, isEmpty); // asking changes nothing
    expect(find.text('Preview plan change'), findsOneWidget);

    await tester.tap(find.text('Preview plan change'));
    await tester.pumpAndSettle();
    expect(plans.requests, ['Move my gym to 7 pm today']);
    expect(find.text('Plan changes'), findsOneWidget);
    expect(find.text('Moved Gym'), findsOneWidget);
    expect(plans.applied, 0);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(plans.applied, 1);
    expect(find.text('Plan updated.'), findsOneWidget);
  });

  testWidgets('cancelling the preview dismisses it and changes nothing', (
    tester,
  ) async {
    final plans = await _open(tester);
    await _ask(tester, 'Skip the gym today');
    await tester.tap(find.text('Preview plan change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(plans.dismissed, 1);
    expect(plans.applied, 0);
  });

  testWidgets('questions get no offer', (tester) async {
    await _open(tester);
    await _ask(tester, 'What should I prioritize tonight?');
    expect(find.text('Preview plan change'), findsNothing);
  });

  testWidgets('no offer without today’s plan or in sample mode', (
    tester,
  ) async {
    await _open(tester, withPlan: false);
    await _ask(tester, 'Move my gym to 7 pm today');
    expect(find.text('Preview plan change'), findsNothing);

    await _open(tester, sample: true);
    await _ask(tester, 'Move my gym to 7 pm today');
    expect(find.text('Preview plan change'), findsNothing);
  });
}
