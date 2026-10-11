import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/goals/data/api_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

Goal draft({
  double? target = 30,
  double? current = 22.5,
  String? unit = 'kg',
}) => Goal(
  id: 'draft',
  title: 'Lift 30 kg',
  category: OmniaCategory.activity,
  targetValue: target,
  currentValue: target == null ? null : current,
  unit: target == null ? null : unit,
  deadline: DateTime(2026, 12, 31),
);

FakeAuthBackend backend() => FakeAuthBackend()
  ..addUser('Sam', sam, 'password-123', signedIn: true)
  ..addUser('Ada', ada, 'ada-password');

void main() {
  group('ApiGoalRepository', () {
    test('creates with a server id and maps every field', () async {
      final fake = backend();
      final api = fake.client();
      addTearDown(api.close);
      await api.restoreToken();
      final repository = ApiGoalRepository(api);

      final created = await repository.createGoal(draft());
      expect(created.id, startsWith('goal-uuid-'));
      expect(created.id, isNot('draft'));
      expect(created.currentValue, 22.5);
      expect(created.targetValue, 30);
      expect(created.unit, 'kg');
      expect(created.deadline, DateTime(2026, 12, 31));
      expect(created.category, OmniaCategory.activity);
      expect(fake.goalsOf(sam).single['deadline'], '2026-12-31');

      final done = await repository.setCompleted(created.id, true);
      expect(done.completed, isTrue);
      expect(done.currentValue, 22.5);

      final simple = await repository.updateGoal(
        done.copyWith(targetValue: null, currentValue: null, unit: null),
      );
      expect(simple.measurable, isFalse);

      expect((await repository.getGoals()).single.id, created.id);
      await repository.deleteGoal(created.id);
      expect(await repository.getGoals(), isEmpty);
    });

    test('goals stay with their account', () async {
      final fake = backend();
      final api = fake.client();
      addTearDown(api.close);
      await api.restoreToken();
      final mine = await ApiGoalRepository(api).createGoal(draft());
      final adaApi = fake.client();
      addTearDown(adaApi.close);
      final auth = AuthController(adaApi);
      addTearDown(auth.dispose);
      await auth.signIn(ada, 'ada-password');
      final theirs = ApiGoalRepository(adaApi);
      expect(await theirs.getGoals(), isEmpty);
      await expectLater(
        theirs.getGoal(mine.id),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'nf', true)),
      );
    });
  });

  testWidgets('goals made in API mode survive a restart of the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = backend();
    final api = fake.client();
    addTearDown(api.close);
    await tester.pumpWidget(OmniaApp(api: api));
    await tester.pumpAndSettle();
    final goals = GoalScope.of(tester.element(find.byType(HomePage)));
    expect(await goals.create(draft()), isTrue);
    expect(fake.goalWrites.single, startsWith('POST goal-uuid-'));

    // A fresh app (and session) loads the same goal from the server.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(OmniaApp(api: api));
    await tester.pumpAndSettle();
    final reloaded = GoalScope.of(tester.element(find.byType(HomePage)));
    await reloaded.load();
    expect(reloaded.active.single.title, 'Lift 30 kg');
    expect(reloaded.active.single.id, startsWith('goal-uuid-'));
  });
}
