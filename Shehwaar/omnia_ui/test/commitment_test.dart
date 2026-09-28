import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/commitment_form_page.dart';
import 'package:omnia_ui/features/plan/data/api_commitment_repository.dart';
import 'package:omnia_ui/features/plan/data/mock_commitment_repository.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_preferences_page.dart';
import 'package:omnia_ui/features/plan/widgets/daily_plan_view.dart';

import 'plan_api_test.dart' show payload;
import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com';

Map<String, dynamic> college({int start = 555, int end = 945}) => {
  'title': 'College',
  'category': 'college',
  'kind': 'recurring',
  'weekdays': [0, 1, 2, 3, 4],
  'day': null,
  'start_minutes': start,
  'end_minutes': end,
  'enabled': true,
};

Future<void> openPreferences(WidgetTester tester) async {
  await tester.tap(find.text('Plan').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Plan preferences'));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, String text, Type page) async {
  await tester.scrollUntilVisible(
    find.text(text),
    180,
    scrollable: find
        .descendant(of: find.byType(page), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'create, edit, pause and delete recurring commitment without rewriting plan',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.dashboardDate = '2026-09-28';
      backend.plans[sam] = {...payload, 'plan_date': backend.dashboardDate};
      final api = backend.client();
      addTearDown(api.close);
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      await openPreferences(tester);
      await reveal(tester, 'Add regular commitment', PlanPreferencesPage);
      await tester.tap(find.text('Add regular commitment'));
      await tester.pumpAndSettle();
      expect(find.byType(CommitmentFormPage), findsOneWidget);
      await tester.tap(find.text('Sat'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Save commitment', CommitmentFormPage);
      await tester.tap(find.text('Save commitment'));
      await tester.pumpAndSettle();
      expect(backend.commitmentsOf(sam).single['weekdays'], [0, 1, 2, 3, 4, 5]);
      expect(find.text('College'), findsOneWidget);
      await tester.tap(find.text('College'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commute'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Active', CommitmentFormPage);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Save commitment', CommitmentFormPage);
      await tester.tap(find.text('Save commitment'));
      await tester.pumpAndSettle();
      expect(backend.commitmentsOf(sam).single['title'], 'Commute');
      expect(backend.commitmentsOf(sam).single['category'], 'commute');
      expect(backend.commitmentsOf(sam).single['enabled'], isFalse);
      await tester.tap(find.text('Commute'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Active', CommitmentFormPage);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Save commitment', CommitmentFormPage);
      await tester.tap(find.text('Save commitment'));
      await tester.pumpAndSettle();
      expect(backend.commitmentsOf(sam).single['enabled'], isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('FIXED COMMITMENT'), findsOneWidget);
      expect(find.text('Commute'), findsOneWidget);
      final plan = PlanScope.of(tester.element(find.byType(DailyPlanView)));
      expect(plan.plan!.items.single.start, '19:00');
      expect(plan.mayBeStale, isTrue);
      expect(find.textContaining('snapshot is unchanged'), findsOneWidget);
      expect(backend.plans[sam]!['items'], payload['items']);
      await tester.tap(find.byTooltip('Plan preferences'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Commute', PlanPreferencesPage);
      await tester.tap(find.text('Commute'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Delete commitment', CommitmentFormPage);
      await tester.tap(find.text('Delete commitment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(backend.commitmentsOf(sam), isEmpty);
    },
  );

  testWidgets('one-off picker, validation, and 12/24-hour fixed timeline', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', sam, 'password-123', signedIn: true);
    backend.dashboardDate = DateTime.now().toIso8601String().substring(0, 10);
    backend.profileOf(sam)!['time_format'] = '12h';
    final api = backend.client();
    addTearDown(api.close);
    await tester.pumpWidget(OmniaApp(api: api));
    await tester.pumpAndSettle();
    await openPreferences(tester);
    await reveal(tester, 'Add one-off commitment', PlanPreferencesPage);
    await tester.tap(find.text('Add one-off commitment'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Save commitment', CommitmentFormPage);
    await tester.tap(find.text('Save commitment'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Add a name, valid same-day times'),
      findsOneWidget,
    );
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Save commitment', CommitmentFormPage);
    await tester.tap(find.text('Save commitment'));
    await tester.pumpAndSettle();
    expect(backend.commitmentsOf(sam).single['kind'], 'one_off');
    expect(backend.commitmentsOf(sam).single['day'], backend.dashboardDate);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('FIXED COMMITMENT'), findsOneWidget);
    expect(find.textContaining('9:00 AM'), findsWidgets);
    await tester.tap(find.byTooltip('Plan preferences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24-hour'));
    await reveal(tester, 'Save', PlanPreferencesPage);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('09:00'), findsWidgets);
  });

  testWidgets('full-day busy state and account switch stay isolated', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', sam, 'password-123', signedIn: true)
      ..addUser('Ada', 'ada@example.com', 'password-456');
    backend.dashboardDate = '2026-09-28';
    final api = backend.client();
    addTearDown(api.close);
    await tester.pumpWidget(OmniaApp(api: api));
    await tester.pumpAndSettle();
    await api.post('/commitments', body: college(start: 480, end: 1320));
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    final first = CommitmentScope.maybeOf(
      tester.element(find.byType(DailyPlanView)),
    )!;
    await first.loadForDate(DateTime(2026, 9, 28), force: true);
    await tester.pumpAndSettle();
    expect(find.text('No free planning time.'), findsOneWidget);
    expect(find.text('FIXED COMMITMENT'), findsOneWidget);
    final auth = AuthScope.of(tester.element(find.byType(DailyPlanView)));
    await auth.signOut();
    await tester.pumpAndSettle();
    await auth.signIn('ada@example.com', 'password-456');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    final second = CommitmentScope.maybeOf(
      tester.element(find.byType(DailyPlanView)),
    )!;
    expect(identical(first, second), isFalse);
    expect(backend.commitmentsOf('ada@example.com'), isEmpty);
    expect(find.text('FIXED COMMITMENT'), findsNothing);
  });

  testWidgets(
    'current commitment flags an overlapping saved snapshot after restart',
    (tester) async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.dashboardDate = '2026-09-28';
      backend.plans[sam] = {...payload, 'plan_date': backend.dashboardDate};
      final api = backend.client();
      addTearDown(api.close);
      await api.restoreToken();
      await api.post(
        '/commitments',
        body: college(start: 18 * 60, end: 20 * 60),
      );
      await tester.pumpWidget(OmniaApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan').last);
      await tester.pumpAndSettle();
      expect(find.text('FIXED COMMITMENT'), findsOneWidget);
      expect(
        find.textContaining('overlaps this saved suggestion'),
        findsOneWidget,
      );
      expect(backend.plans[sam]!['items'], payload['items']);
    },
  );

  test('commitment date relevance respects weekdays, one-off day, and disabled state', () {
    final recurring = CommitmentDraft(
      title: 'College',
      category: 'college',
      kind: 'recurring',
      weekdays: const [0, 2],
      day: null,
      startMinutes: 540,
      endMinutes: 600,
      enabled: true,
    );
    expect(recurring.appliesOn(DateTime(2026, 9, 28)), isTrue);
    expect(recurring.appliesOn(DateTime(2026, 9, 29)), isFalse);
    final oneOff = CommitmentDraft(
      title: 'Doctor',
      category: 'appointment',
      kind: 'one_off',
      weekdays: const [],
      day: DateTime(2026, 10, 3),
      startMinutes: 840,
      endMinutes: 900,
      enabled: false,
    );
    expect(oneOff.appliesOn(DateTime(2026, 10, 3)), isFalse);
  });

  test(
    'API repository round-trips commitment and selected-date projection',
    () async {
      final backend = FakeAuthBackend()
        ..addUser('Sam', sam, 'password-123', signedIn: true);
      backend.dashboardDate = '2026-09-28';
      final api = backend.client();
      addTearDown(api.close);
      await api.restoreToken();
      final repository = ApiCommitmentRepository(api);
      final saved = await repository.save(
        const CommitmentDraft(
          title: 'College',
          category: 'college',
          kind: 'recurring',
          weekdays: [0, 1, 2, 3, 4],
          day: null,
          startMinutes: 555,
          endMinutes: 945,
          enabled: true,
        ),
      );
      expect((await repository.list()).single.id, saved.id);
      final monday = await repository.availability(day: DateTime(2026, 9, 28));
      expect(monday.commitments.single.title, 'College');
      expect(monday.freeIntervals.first.endMinutes, 555);
      final sunday = await repository.availability(day: DateTime(2026, 10, 4));
      expect(sunday.commitments, isEmpty);
      await repository.delete(saved.id);
      expect(await repository.list(), isEmpty);
    },
  );

  test('mock repository keeps date-specific commitments in memory', () async {
    final repository = MockCommitmentRepository();
    await repository.save(
      CommitmentDraft(
        title: 'Appointment',
        category: 'appointment',
        kind: 'one_off',
        weekdays: const [],
        day: DateTime(2026, 10, 3),
        startMinutes: 840,
        endMinutes: 900,
        enabled: true,
      ),
    );
    expect(
      (await repository.availability(day: DateTime(2026, 10, 3)))
          .commitments
          .single
          .title,
      'Appointment',
    );
    expect(
      (await repository.availability(day: DateTime(2026, 10, 4))).commitments,
      isEmpty,
    );
  });
}
