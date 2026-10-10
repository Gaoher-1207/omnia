import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/replan_change_format.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';

import 'support/fake_auth_backend.dart';

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
      'start': '16:30',
      'end': '17:30',
      'category': 'task',
      'title': 'Assignment',
      'task_id': 'task-1',
    },
  ],
};

Map<String, dynamic> _block(
  String title,
  String start,
  String end, {
  String category = 'task',
}) => {
  'start': start,
  'end': end,
  'category': category,
  'title': title,
  'task_id': null,
  'subject_id': null,
};

Map<String, dynamic> _op(
  String kind, {
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) => {
  'kind': kind,
  'item_key': 'key-$kind',
  'entity_id': null,
  'before': before,
  'after': after,
  'reason': 'Reason for $kind.',
};

final _operations = [
  _op(
    'REMOVE',
    before: _block('Evening Workout', '16:30', '17:30', category: 'fitness'),
  ),
  _op('ADD', after: _block('Revision', '19:00', '20:00', category: 'study')),
  _op(
    'MOVE',
    before: _block('Assignment', '16:30', '17:30'),
    after: _block('Assignment', '18:00', '19:00'),
  ),
  _op(
    'SHORTEN',
    before: _block('Revision', '14:00', '15:00'),
    after: _block('Revision', '14:00', '14:30'),
  ),
  _op(
    'RESCHEDULE',
    before: _block('DBMS revision', '17:00', '18:00'),
    after: _block('DBMS revision', '19:00', '20:30'),
  ),
  _op(
    'UNCHANGED',
    before: _block('Reading', '21:00', '21:30'),
    after: _block('Reading', '21:00', '21:30'),
  ),
];

Map<String, dynamic> _proposalJson({
  List<Map<String, dynamic>>? operations,
  String status = 'pending',
}) => {
  'id': 'proposal-1',
  'base_plan_id': 'plan-1',
  'base_revision': 4,
  'plan_date': '2026-09-27',
  'status': status,
  'request': 'Skip the gym and fit in revision',
  'summary': 'Technical summary of the proposal.',
  'explanation': 'Internal explanation of the proposal.',
  'operations': operations ?? _operations,
  'schedule': [
    {
      'item_key': 'task-key',
      'start': '18:00',
      'end': '19:00',
      'category': 'task',
      'title': 'Full schedule entry',
      'task_id': 'task-1',
    },
  ],
  'warnings': ['Validation warning text.'],
  'validation': {'valid': true, 'applicable': true},
  'created_at': '2026-09-27T19:00:00Z',
  'expires_at': '2026-09-27T19:30:00Z',
};

ReplanOperation _parsed(Map<String, dynamic> json) =>
    ReplanOperation.fromJson(json);

void main() {
  group('replan change formatter', () {
    test('returns only the action and item title', () {
      expect(describeReplanChanges(_operations.map(_parsed)), [
        'Removed Evening Workout',
        'Added Revision',
        'Moved Assignment',
        'Shortened Revision',
        'Rescheduled DBMS revision',
      ]);
    });

    test('never includes times, durations or "today"', () {
      for (final line in describeReplanChanges(_operations.map(_parsed))) {
        expect(line, isNot(matches(RegExp(r'\d'))), reason: line);
        for (final hidden in [':', 'AM', 'PM', 'min', 'hr', 'today', '·']) {
          expect(line, isNot(contains(hidden)), reason: '$line has $hidden');
        }
      }
    });

    test('hides UNCHANGED operations', () {
      final unchanged = _parsed(_operations.last);
      expect(describeReplanChange(unchanged), isNull);
      expect(describeReplanChanges([unchanged]), isEmpty);
    });

    test('prefers the new title and falls back to the old one', () {
      final renamed = _parsed(
        _op(
          'MOVE',
          before: _block('Old name', '09:00', '10:00'),
          after: _block('New name', '10:00', '11:00'),
        ),
      );
      expect(describeReplanChange(renamed), 'Moved New name');
      final untitled = _parsed(
        _op(
          'MOVE',
          before: _block('Old name', '09:00', '10:00'),
          after: {..._block('', '10:00', '11:00'), 'title': null},
        ),
      );
      expect(describeReplanChange(untitled), 'Moved Old name');
    });
  });

  group('plan controller proposal lifecycle', () {
    test(
      'creation reloads the persisted proposal and leaves the plan',
      () async {
        final repository = _ReplanRepository();
        final controller = _readyController(repository);
        expect(await controller.createReplanProposal('Skip the gym'), isTrue);
        expect(repository.createCalls, 1);
        expect(repository.getProposalCalls, 1);
        expect(repository.applyCalls, 0);
        expect(repository.lastRequest, 'Skip the gym');
        expect(controller.replanProposal?.id, 'proposal-1');
        expect(controller.plan?.revision, 4);
        controller.dispose();
      },
    );

    test('apply runs once and refreshes the displayed plan', () async {
      final repository = _ReplanRepository()..appliedPlan = _newPlan(5);
      final controller = _readyController(repository);
      await controller.createReplanProposal('Skip the gym');
      expect(await controller.applyReplanProposal(), isTrue);
      expect(await controller.applyReplanProposal(), isFalse);
      expect(repository.applyCalls, 1);
      expect(repository.readCalls, 1);
      expect(controller.plan?.revision, 5);
      expect(controller.todayPlan?.revision, 5);
      expect(controller.replanProposal, isNull);
      expect(controller.replanNotice, 'Plan updated.');
      controller.dispose();
    });

    test('concurrent apply taps reach the backend once', () async {
      final repository = _ReplanRepository();
      final controller = _readyController(repository);
      await controller.createReplanProposal('Skip the gym');
      final results = await Future.wait([
        controller.applyReplanProposal(),
        controller.applyReplanProposal(),
      ]);
      expect(results, [true, false]);
      expect(repository.applyCalls, 1);
      controller.dispose();
    });

    test('dismissal calls the backend and clears the preview', () async {
      final repository = _ReplanRepository();
      final controller = _readyController(repository);
      await controller.createReplanProposal('Skip the gym');
      expect(await controller.dismissReplanProposal(), isTrue);
      expect(repository.dismissCalls, 1);
      expect(repository.applyCalls, 0);
      expect(controller.replanProposal, isNull);
      expect(controller.plan?.revision, 4);
      controller.dispose();
    });

    test('stale proposal refreshes the plan with a short notice', () async {
      final repository = _ReplanRepository()
        ..applyFailure = const ApiException(
          statusCode: 409,
          code: 'replan_proposal_stale',
          message: 'Stale proposal',
        )
        ..currentPlan = _newPlan(6);
      final controller = _readyController(repository);
      await controller.createReplanProposal('Skip the gym');
      expect(await controller.applyReplanProposal(), isFalse);
      expect(repository.readCalls, 1);
      expect(controller.replanProposal, isNull);
      expect(controller.plan?.revision, 6);
      expect(controller.replanNotice, contains('plan changed'));
      controller.dispose();
    });

    for (final (code, status, notice) in [
      ('replan_proposal_expired', 409, 'This preview expired.'),
      ('replan_invalid', 422, 'can no longer be applied'),
      ('replan_proposal_conflict', 409, 'can no longer be applied'),
    ]) {
      test('$code retires the preview without changing the plan', () async {
        final repository = _ReplanRepository()
          ..applyFailure = ApiException(
            statusCode: status,
            code: code,
            message: 'Backend detail',
          );
        final controller = _readyController(repository);
        await controller.createReplanProposal('Skip the gym');
        expect(await controller.applyReplanProposal(), isFalse);
        expect(controller.replanProposal, isNull);
        expect(controller.plan?.revision, 4);
        expect(controller.replanNotice, contains(notice));
        expect(controller.replanNotice, contains('Nothing was changed'));
        controller.dispose();
      });
    }

    test('provider/API errors are surfaced and actions unlock', () async {
      final repository = _ReplanRepository()
        ..createFailure = const ApiException(
          statusCode: 503,
          code: 'provider_unavailable',
          message: 'Planner unavailable',
        );
      final controller = PlanController(repository);
      expect(await controller.createReplanProposal('Skip the gym'), isFalse);
      expect(controller.replanError, isA<ApiException>());
      expect(controller.creatingProposal, isFalse);
      expect(controller.replanProposal, isNull);
      controller.dispose();
    });

    test('a failed apply keeps the preview for a retry', () async {
      final repository = _ReplanRepository()
        ..applyFailure = ApiException.network();
      final controller = _readyController(repository);
      await controller.createReplanProposal('Skip the gym');
      expect(await controller.applyReplanProposal(), isFalse);
      expect(controller.replanProposal, isNotNull);
      expect(controller.replanError, isA<ApiException>());
      expect(controller.proposalActionBusy, isFalse);
      expect(controller.plan?.revision, 4);
      controller.dispose();
    });
  });

  group('adjust today’s plan preview', () {
    testWidgets('shows only action-and-title lines, then applies', (
      tester,
    ) async {
      final repository = _ReplanRepository()..appliedPlan = _newPlan(5);
      final controller = _readyController(repository);
      await _pump(tester, controller);

      await _openPreview(tester);
      final sheet = find.byType(BottomSheet);
      Finder inSheet(Finder finder) =>
          find.descendant(of: sheet, matching: finder);
      expect(inSheet(find.text('Plan changes')), findsOneWidget);
      final lines = [
        'Removed Evening Workout',
        'Added Revision',
        'Moved Assignment',
        'Shortened Revision',
        'Rescheduled DBMS revision',
      ];
      for (final line in lines) {
        expect(inSheet(find.text(line)), findsOneWidget);
      }
      // Every text in the sheet is the heading, a change line, a bullet or
      // an action label: nothing else from the proposal can leak in.
      final texts = tester
          .widgetList<Text>(inSheet(find.byType(Text)))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .map((text) => text.trim())
          .where((text) => text.isNotEmpty)
          .toSet();
      expect(texts, {'Plan changes', '•', ...lines, 'Apply', 'Cancel'});
      for (final hidden in [
        // Times, durations and day words.
        '16:30', '17:30', '18:00', '19:00', '20:30', 'PM', 'AM', 'min', 'hr',
        'today',
        // Summary, explanation, reasons, warnings and the full schedule.
        'Technical summary of the proposal.',
        'Internal explanation of the proposal.',
        'Reason for',
        'Validation warning text.',
        'Full schedule entry',
        'Proposed', 'Changes to today', 'Warnings',
        // Raw before/after, categories, operation names, IDs and revisions.
        'Before', 'After', 'fitness', 'study', 'MOVE', 'UNCHANGED', 'Reading',
        'key-', 'task-1', 'proposal-1', 'plan-1', 'Revision 4', 'valid',
        'pending', 'rules',
      ]) {
        expect(
          inSheet(find.textContaining(hidden)),
          findsNothing,
          reason: hidden,
        );
      }
      expect(repository.applyCalls, 0);
      expect(controller.plan?.revision, 4);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(repository.applyCalls, 1);
      expect(repository.dismissCalls, 0);
      expect(controller.plan?.revision, 5);
      expect(find.text('Plan changes'), findsNothing);
      expect(find.text('Plan updated.'), findsOneWidget);
      expect(find.textContaining('Revision 5'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lines stay time-free with the 12-hour profile setting', (
      tester,
    ) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', 'sam@example.com', 'password-123', signedIn: true);
      backend.profileOf('sam@example.com')!['time_format'] = '12h';
      final api = backend.client();
      addTearDown(api.close);
      final auth = AuthController(api);
      addTearDown(auth.dispose);
      await auth.restore();
      final controller = _readyController(_ReplanRepository());
      await _pump(tester, controller, auth: auth);

      await _openPreview(tester);
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Moved Assignment')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('PM')),
        findsNothing,
      );
    });

    testWidgets('cancel dismisses without applying', (tester) async {
      final repository = _ReplanRepository();
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.dismissCalls, 1);
      expect(repository.applyCalls, 0);
      expect(controller.plan?.revision, 4);
      expect(find.text('Plan changes'), findsNothing);
    });

    testWidgets('closing the sheet discards the preview', (tester) async {
      final repository = _ReplanRepository();
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(repository.dismissCalls, 1);
      expect(repository.applyCalls, 0);
      expect(controller.replanProposal, isNull);
    });

    testWidgets('shows only "No changes needed." without visible changes', (
      tester,
    ) async {
      final repository = _ReplanRepository()
        ..proposal = _proposalJson(operations: [_operations.last]);
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      expect(find.text('No changes needed.'), findsOneWidget);
      expect(find.text('Reading'), findsNothing);
      expect(find.text('Apply'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(repository.dismissCalls, 1);
      expect(repository.applyCalls, 0);
    });

    testWidgets('stale apply closes the preview with a short notice', (
      tester,
    ) async {
      final repository = _ReplanRepository()
        ..applyFailure = const ApiException(
          statusCode: 409,
          code: 'replan_proposal_stale',
          message: 'The plan or planning state changed after this proposal.',
        )
        ..currentPlan = _newPlan(6);
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Plan changes'), findsNothing);
      expect(find.textContaining('plan changed'), findsOneWidget);
      expect(repository.dismissCalls, 0);
      expect(controller.plan?.revision, 6);
    });

    testWidgets('API errors stay inline and keep Apply available', (
      tester,
    ) async {
      final repository = _ReplanRepository()
        ..applyFailure = const ApiException(
          statusCode: 503,
          code: 'provider_unavailable',
          message: 'Planner unavailable. Try again.',
        );
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Planner unavailable. Try again.'), findsOneWidget);
      expect(find.text('Plan changes'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(controller.plan?.revision, 4);
    });

    testWidgets('create failures show a snackbar and no preview', (
      tester,
    ) async {
      final repository = _ReplanRepository()
        ..createFailure = const ApiException(
          statusCode: 503,
          code: 'provider_unavailable',
          message: 'Planner unavailable.',
        );
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await _openPreview(tester);
      expect(find.text('Planner unavailable.'), findsOneWidget);
      expect(find.text('Plan changes'), findsNothing);
    });

    testWidgets('an empty request is not sent', (tester) async {
      final repository = _ReplanRepository();
      final controller = _readyController(repository);
      await _pump(tester, controller);
      await tester.tap(find.text('Adjust today’s plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview changes'));
      await tester.pumpAndSettle();
      expect(find.text('Describe the change you want'), findsOneWidget);
      expect(repository.createCalls, 0);
    });

    testWidgets('the entry point is limited to today’s plan', (tester) async {
      final controller = _readyController(_ReplanRepository());
      await _pump(tester, controller);
      expect(find.text('Adjust today’s plan'), findsOneWidget);
      await controller.selectDate(DateTime(2026, 9, 26));
      await tester.pumpAndSettle();
      expect(find.text('Adjust today’s plan'), findsNothing);

      final empty = PlanController(_ReplanRepository());
      empty.seedToday(DateTime(2026, 9, 27), null);
      await _pump(tester, empty);
      expect(find.text('Adjust today’s plan'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('preview fits a narrow phone at 200% text in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = _readyController(_ReplanRepository());
        await _pump(tester, controller, brightness: brightness, textScale: 2);
        await _openPreview(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Plan changes'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Apply'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Apply').hitTestable(), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
      });
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  PlanController controller, {
  AuthController? auth,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  final focus = FocusTimerController();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  Widget app = PlanScope(
    controller: controller,
    child: FocusTimerScope(
      controller: focus,
      child: MaterialApp(
        theme: buildAppTheme(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: DailyPlanView(today: DateTime(2026, 9, 27))),
      ),
    ),
  );
  if (auth != null) app = AuthScope(controller: auth, child: app);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _openPreview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Adjust today’s plan'),
    200,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Adjust today’s plan'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Skip the gym');
  await tester.tap(find.text('Preview changes'));
  await tester.pumpAndSettle();
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
  Map<String, dynamic> proposal = _proposalJson();
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
    return ReplanProposal.fromJson(proposal);
  }

  @override
  Future<ReplanProposal> getReplanProposal(String proposalId) async {
    getProposalCalls++;
    return ReplanProposal.fromJson(proposal);
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
    return ReplanProposal.fromJson({...proposal, 'status': 'dismissed'});
  }
}
