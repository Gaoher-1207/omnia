import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';

/// `/api/goals`: long-term goals saved to the signed-in account. The server
/// assigns ids, so callers must use the returned entities.
class ApiGoalRepository implements GoalRepository {
  ApiGoalRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Goal>> getGoals() async =>
      asMapList(await _api.get('/goals')).map(goalFromApi).toList();

  @override
  Future<Goal> getGoal(String id) async =>
      goalFromApi(asMap(await _api.get('/goals/$id')));

  @override
  Future<Goal> createGoal(Goal goal) async =>
      goalFromApi(asMap(await _api.post('/goals', body: goalToApi(goal))));

  /// Sends every editable field, so clearing a value on the form clears it
  /// on the server too.
  @override
  Future<Goal> updateGoal(Goal goal) async => goalFromApi(
    asMap(await _api.patch('/goals/${goal.id}', body: goalToApi(goal))),
  );

  @override
  Future<Goal> setCompleted(String id, bool completed) async => goalFromApi(
    asMap(await _api.patch('/goals/$id', body: {'completed': completed})),
  );

  @override
  Future<void> deleteGoal(String id) => _api.delete('/goals/$id');
}

Goal goalFromApi(Map<String, dynamic> json) => Goal(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  category: OmniaCategory.values.byName(json['category'] as String),
  targetValue: (json['target_value'] as num?)?.toDouble(),
  currentValue: (json['current_value'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  completed: json['completed'] as bool,
  deadline: json['deadline'] == null
      ? null
      : parseDay(json['deadline'] as String),
);

/// `GoalCreate` / `GoalUpdate`. The deadline is a calendar day.
Map<String, Object?> goalToApi(Goal goal) => {
  'title': goal.title,
  'description': goal.description,
  'category': goal.category.name,
  'target_value': goal.targetValue,
  'current_value': goal.currentValue,
  'unit': goal.unit,
  'deadline': goal.deadline == null ? null : formatDay(goal.deadline!),
  'completed': goal.completed,
};
