import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

abstract interface class PlanRepository {
  /// Null only when the server has no suggestion for its current local day.
  Future<DailyPlan?> getToday({DateTime? date});

  /// Explicitly generate a new snapshot; never marks any work complete.
  Future<DailyPlan> generate();
}
