import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';

/// Optional persisted-suggestion fixture. The existing mock timeline remains a
/// labelled visual sample; mock mode does not pretend to run a planner.
class MockPlanRepository implements PlanRepository {
  MockPlanRepository([this.plan]);
  final DailyPlan? plan;
  @override
  Future<DailyPlan?> getToday({DateTime? date}) async =>
      date == null || plan?.date == date ? plan : null;
  @override
  Future<DailyPlan> generate() async =>
      plan ?? (throw StateError('Plan generation requires API mode.'));

  @override
  Future<Never> createReplanProposal(String request, {DateTime? date}) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> getReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> applyReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> dismissReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');
}
