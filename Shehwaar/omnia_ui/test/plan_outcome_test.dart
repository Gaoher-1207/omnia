import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/plan/data/api_plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';

Map<String, dynamic> _planJson({
  String? outcome,
  String id = 'plan-1',
  String category = 'task',
  int? minutes,
}) => {
  'id': id,
  'revision': 1,
  'plan_date': '2026-09-27',
  'created_at': '2026-09-27T08:00:00Z',
  'source': 'rules',
  'is_fallback': false,
  'summary': 'Assignment first.',
  'items': [
    {
      'item_key': 'task-key',
      'start': '09:00',
      'end': '09:30',
      'category': category,
      'title': 'Assignment',
      'task_id': 'task-1',
      'outcome': outcome,
      'outcome_minutes': minutes,
    },
  ],
};

class _OutcomeRepository implements PlanRepository {
  @override
  Future<Never> addItem(
    DateTime day,
    ManualPlanItemDraft draft, {
    int? baseRevision,
  }) => throw UnimplementedError();

  @override
  Future<Never> removeItem(DateTime day, String itemKey, {int? baseRevision}) =>
      throw UnimplementedError();

  _OutcomeRepository({this.category = 'task', this.onDone})
    : current = DailyPlan.fromJson(_planJson(category: category));
  final String category;
  final Future<void> Function()? onDone;
  DailyPlan current;
  Object? failure;
  final calls = <(DateTime, String, String?)>[];
  final minutesSent = <int?>[];
  int reads = 0;

  @override
  Future<DailyPlan?> getToday({DateTime? date}) async {
    reads++;
    return current;
  }

  @override
  Future<DailyPlan> generate() async => current;

  @override
  Future<DailyPlan> recordOutcome(
    DateTime day,
    String itemKey,
    String? status, {
    int? minutes,
  }) async {
    calls.add((day, itemKey, status));
    minutesSent.add(minutes);
    if (failure case final error?) throw error;
    if (status == 'done') await onDone?.call();
    current = DailyPlan.fromJson(
      _planJson(outcome: status, category: category, minutes: minutes),
    );
    return current;
  }

  @override
  Future<Never> createReplanProposal(String request, {DateTime? date}) =>
      throw UnimplementedError();
  @override
  Future<Never> getReplanProposal(String proposalId) =>
      throw UnimplementedError();
  @override
  Future<Never> applyReplanProposal(String proposalId) =>
      throw UnimplementedError();
  @override
  Future<ReplanProposal> dismissReplanProposal(String proposalId) =>
      throw UnimplementedError();
}

PlanController _ready(_OutcomeRepository repository) =>
    PlanController(repository)
      ..seedToday(DateTime(2026, 9, 27), repository.current);

Future<void> _pump(
  WidgetTester tester,
  PlanController controller, {
  DateTime? today,
  Brightness brightness = Brightness.light,
  TaskController? tasks,
}) async {
  final focus = FocusTimerController();
  final taskController = tasks ?? TaskController(MockTaskRepository());
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  addTearDown(taskController.dispose);
  await tester.pumpWidget(
    PlanScope(
      controller: controller,
      child: TaskScope(
        controller: taskController,
        child: FocusTimerScope(
          controller: focus,
          child: MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Scaffold(
              body: DailyPlanView(today: today ?? DateTime(2026, 9, 27)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the API records with PUT and clears with DELETE', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'http://test/api',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = request.method == 'DELETE'
            ? _planJson()
            : _planJson(outcome: 'done');
        return http.Response(jsonEncode(body), 200);
      }),
    );
    addTearDown(api.close);
    final repository = ApiPlanRepository(api);
    final done = await repository.recordOutcome(
      DateTime(2026, 9, 27),
      'task-key',
      'done',
    );
    expect(done.items.single.outcome, 'done');
    expect(requests.last.method, 'PUT');
    expect(
      requests.last.url.path,
      '/api/ai/daily-plan/2026-09-27/items/task-key/outcome',
    );
    expect(jsonDecode(requests.last.body), {'status': 'done'});

    final cleared = await repository.recordOutcome(
      DateTime(2026, 9, 27),
      'task-key',
      null,
    );
    expect(cleared.items.single.outcome, isNull);
    expect(requests.last.method, 'DELETE');
  });

  test(
    'a recorded outcome updates the plan and Today without a reload',
    () async {
      final repository = _OutcomeRepository();
      final controller = _ready(repository);
      final item = controller.plan!.items.single;
      expect(item.outcome, isNull);
      expect(await controller.recordOutcome(item, 'done'), isTrue);
      expect(repository.calls.single, (
        DateTime(2026, 9, 27),
        'task-key',
        'done',
      ));
      expect(controller.plan!.items.single.outcome, 'done');
      expect(controller.todayPlan!.items.single.outcome, 'done');
      expect(repository.reads, 0);
      controller.dispose();
    },
  );

  test('one write per block at a time', () async {
    final repository = _OutcomeRepository();
    final controller = _ready(repository);
    final item = controller.plan!.items.single;
    final results = await Future.wait([
      controller.recordOutcome(item, 'done'),
      controller.recordOutcome(item, 'skipped'),
    ]);
    expect(results, [true, false]);
    expect(repository.calls, hasLength(1));
    controller.dispose();
  });

  test('a block missing from the latest plan refreshes the plan', () async {
    final repository = _OutcomeRepository()
      ..failure = const ApiException(
        statusCode: 409,
        code: 'plan_item_stale',
        message: 'This block is no longer in the latest plan.',
      );
    final controller = _ready(repository);
    repository.current = DailyPlan.fromJson(_planJson(id: 'plan-2'));
    expect(
      await controller.recordOutcome(controller.plan!.items.single, 'done'),
      isFalse,
    );
    expect(repository.reads, 1);
    expect(controller.plan!.id, 'plan-2');
    expect(controller.outcomeError, isA<ApiException>());
    expect(controller.outcomeBusy('task-key'), isFalse);
    controller.dispose();
  });

  test('other failures keep the plan and report the error', () async {
    final repository = _OutcomeRepository()..failure = ApiException.network();
    final controller = _ready(repository);
    final before = controller.plan;
    expect(
      await controller.recordOutcome(controller.plan!.items.single, 'done'),
      isFalse,
    );
    expect(controller.plan, same(before));
    expect(controller.outcomeError, isA<ApiException>());
    controller.dispose();
  });

  Finder control(String label) => find.bySemanticsLabel(label);

  Color? fillOf(WidgetTester tester, String label) {
    final box = tester.widget<Container>(
      find
          .descendant(of: control(label), matching: find.byType(Container))
          .first,
    );
    return (box.decoration as BoxDecoration?)?.color;
  }

  testWidgets('the check-off sits inside the block, on the right', (
    tester,
  ) async {
    await _pump(tester, _ready(_OutcomeRepository()));
    const label = 'Not checked off: Assignment. Record what happened';
    expect(control(label), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Assignment'),
      matching: find.byType(HardCard),
    );
    final cardBox = tester.getRect(card);
    final square = tester.getRect(control(label));
    expect(cardBox.contains(square.center), isTrue, reason: 'inside the card');
    expect(square.right, closeTo(cardBox.right - 16, 4), reason: 'right edge');
    expect(
      square.center.dy,
      closeTo(cardBox.center.dy, 3),
      reason: 'vertically centered',
    );
    expect(square.width, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(find.text('Assignment')).right,
      lessThan(square.left),
    );
  });

  testWidgets('completing a task plan block refreshes the Tasks state', (
    tester,
  ) async {
    final taskRepository = MockTaskRepository(
      seed: [
        Task(
          id: 'task-1',
          title: 'Assignment',
          createdAt: DateTime(2026, 9, 27),
        ),
      ],
    );
    final tasks = TaskController(taskRepository);
    await tasks.load();
    expect(tasks.tasks.single.completed, isFalse);
    final repository = _OutcomeRepository(
      onDone: () async {
        await taskRepository.setCompleted('task-1', true);
      },
    );
    await _pump(tester, _ready(repository), tasks: tasks);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    expect(tasks.tasks.single.completed, isTrue);
  });

  testWidgets('each outcome has its own fill and mark; neutral is unfilled', (
    tester,
  ) async {
    final repository = _OutcomeRepository();
    await _pump(tester, _ready(repository));
    final neutral = fillOf(
      tester,
      'Not checked off: Assignment. Record what happened',
    );
    expect(neutral, isNot(anyOf(outcomeDone, outcomePartial, outcomeNotDone)));

    for (final (choice, label, color) in [
      ('Done', 'Done: Assignment. Change', outcomeDone),
      ('Partly done', 'Partly done: Assignment. Change', outcomePartial),
      ('Not done', 'Not done: Assignment. Change', outcomeNotDone),
    ]) {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
      expect(control(label), findsOneWidget, reason: choice);
      expect(fillOf(tester, label), color, reason: choice);
      expect(
        find.descendant(of: control(label), matching: find.byType(CustomPaint)),
        findsWidgets,
      );
    }
    expect(repository.calls.map((call) => call.$3), [
      'done',
      'partial',
      'skipped',
    ]);
    // A task block partly done sends no minutes.
    expect(repository.minutesSent, everyElement(isNull));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.$3, isNull);
    expect(
      control('Not checked off: Assignment. Record what happened'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a partly done study block asks for the minutes studied', (
    tester,
  ) async {
    final repository = _OutcomeRepository(category: 'study');
    await _pump(tester, _ready(repository));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partly done').last);
    await tester.pumpAndSettle();
    expect(find.text('How long did you study?'), findsOneWidget);
    // 30-minute block: 5, 10 … 25 minutes; never the whole block.
    expect(find.text('30 min'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty, reason: 'cancel records nothing');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partly done').last);
    await tester.pumpAndSettle();
    await tester.drag(find.text('10 min'), const Offset(0, -40));
    await tester.pumpAndSettle();
    final save = find.textContaining(RegExp(r'^Save \d+ min$'));
    final chosen = int.parse(
      RegExp(r'\d+').firstMatch(tester.widget<Text>(save).data!)!.group(0)!,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.calls.single.$3, 'partial');
    expect(repository.minutesSent.single, chosen);
    expect(chosen, inInclusiveRange(5, 25));
    expect(find.text('PARTLY DONE · $chosen MIN'), findsOneWidget);
  });

  testWidgets('a failed write explains itself and changes nothing', (
    tester,
  ) async {
    final repository = _OutcomeRepository()
      ..failure = const ApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'Something went wrong on the server.',
      );
    await _pump(tester, _ready(repository));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not done'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong on the server.'), findsOneWidget);
    expect(find.text('NOT DONE'), findsNothing);
  });

  testWidgets(
    'a future day records no outcome; its square only offers removal',
    (tester) async {
      final repository = _OutcomeRepository();
      await _pump(tester, _ready(repository), today: DateTime(2026, 9, 26));
      expect(
        find.bySemanticsLabel('Assignment: checked off on the day'),
        findsOneWidget,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
      expect(find.text('You can check this off on the day.'), findsOneWidget);
      expect(find.text('Hold the square to remove this block'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('outcomes fit a narrow phone at 200% text ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _OutcomeRepository()
        ..current = DailyPlan.fromJson(_planJson(outcome: 'partial'));
      final controller = PlanController(repository)
        ..seedToday(DateTime(2026, 9, 27), repository.current);
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
              home: Scaffold(body: DailyPlanView(today: DateTime(2026, 9, 27))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PARTLY DONE'),
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
      expect(tester.takeException(), isNull);
      final square = control('Partly done: Assignment. Change');
      await tester.ensureVisible(square);
      await tester.pumpAndSettle();
      expect(square.hitTestable(), findsOneWidget);
      expect(tester.getSize(square).width, greaterThanOrEqualTo(44));
      expect(fillOf(tester, 'Partly done: Assignment. Change'), outcomePartial);
    });
  }
}
