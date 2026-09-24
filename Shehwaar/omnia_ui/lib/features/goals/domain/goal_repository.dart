import 'package:omnia_ui/features/goals/domain/goal.dart';

abstract interface class GoalRepository {
  Future<List<Goal>> getGoals();
  Future<Goal> updateGoal(Goal goal);
}
