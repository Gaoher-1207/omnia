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
  Future<Goal> updateGoal(Goal goal) async => _source.update(goal);
}
