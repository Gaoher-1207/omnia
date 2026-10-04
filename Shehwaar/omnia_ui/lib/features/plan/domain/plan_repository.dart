import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';

abstract interface class PlanRepository {
  /// Null only when the server has no suggestion for its current local day.
  Future<DailyPlan?> getToday({DateTime? date});

  /// Explicitly generate a new snapshot; never marks any work complete.
  Future<DailyPlan> generate();

  /// Ask the backend to prepare and validate a preview without changing a plan.
  Future<ReplanProposal> createReplanProposal(String request, {DateTime? date});

  Future<ReplanProposal> getReplanProposal(String proposalId);

  /// Apply is a separate explicit call and returns the new plan snapshot.
  Future<DailyPlan> applyReplanProposal(String proposalId);

  Future<ReplanProposal> dismissReplanProposal(String proposalId);
}
