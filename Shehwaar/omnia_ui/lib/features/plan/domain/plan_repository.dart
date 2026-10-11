import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';

abstract interface class PlanRepository {
  /// Null only when the server has no suggestion for its current local day.
  Future<DailyPlan?> getToday({DateTime? date});

  /// Explicitly generate a new snapshot; never marks any work complete.
  Future<DailyPlan> generate();

  /// Add one block to [day]'s plan as a new revision; nothing else moves.
  /// An overlap is refused (409 `plan_item_conflict`), as is a stale
  /// [baseRevision] (409 `plan_stale`).
  Future<DailyPlan> addItem(
    DateTime day,
    ManualPlanItemDraft draft, {
    int? baseRevision,
  });

  /// Remove the block [itemKey] from [day]'s plan as a new revision; nothing
  /// else changes, and its task, subject and logged study time are kept.
  /// 409 `plan_item_stale` when the block is gone, `plan_stale` when
  /// [baseRevision] is no longer the latest.
  Future<DailyPlan> removeItem(
    DateTime day,
    String itemKey, {
    int? baseRevision,
  });

  /// Ask the backend to prepare and validate a preview without changing a plan.
  Future<ReplanProposal> createReplanProposal(String request, {DateTime? date});

  Future<ReplanProposal> getReplanProposal(String proposalId);

  /// Apply is a separate explicit call and returns the new plan snapshot.
  Future<DailyPlan> applyReplanProposal(String proposalId);

  Future<ReplanProposal> dismissReplanProposal(String proposalId);

  /// Record what happened to one block of [day]'s latest plan (`done`,
  /// `partial`, `skipped`), or clear it with null. Returns the updated plan;
  /// the schedule itself never changes. [minutes] is only for `partial`: the
  /// minutes actually done. The server logs study blocks as study time.
  Future<DailyPlan> recordOutcome(
    DateTime day,
    String itemKey,
    String? status, {
    int? minutes,
  });
}
