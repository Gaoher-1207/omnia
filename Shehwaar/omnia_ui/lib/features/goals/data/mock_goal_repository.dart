import 'package:omnia_ui/core/data/in_memory_data_source.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';

class MockGoalRepository implements GoalRepository {
  MockGoalRepository({Iterable<Goal>? seed})
      : _source = InMemoryDataSource(seed ?? MockData.goals, idOf: (goal) => goal.id);
  final InMemoryDataSource<Goal> _source;

  @override
  Future<List<Goal>> getGoals() async => _source.getAll();
  @override
  Future<Goal> getGoal(String id) async => _source.get(id);
  @override
  Future<Goal> createGoal(Goal goal) async => _source.create(goal);
  @override
  Future<Goal> updateGoal(Goal goal) async => _source.update(goal);
  @override
  Future<Goal> setCompleted(String id, bool completed) async =>
      _source.update(_source.get(id).copyWith(completed: completed));
  @override
  Future<void> deleteGoal(String id) async => _source.delete(id);
}
