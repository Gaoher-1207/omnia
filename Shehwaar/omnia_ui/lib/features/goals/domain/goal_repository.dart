import 'package:omnia_ui/features/goals/domain/goal.dart';

/// IDs are supplied by the caller for now. Always use returned entities: a
/// future API may assign a canonical ID or normalize other fields on creation.
abstract interface class GoalRepository {
  Future<List<Goal>> getGoals();
  Future<Goal> getGoal(String id);
  Future<Goal> createGoal(Goal goal);
  Future<Goal> updateGoal(Goal goal);
  Future<Goal> setCompleted(String id, bool completed);
  Future<void> deleteGoal(String id);
}
