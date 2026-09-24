import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';

/// Daily goals live on the profile; today's progress comes from the dashboard.
class ApiGoalRepository implements GoalRepository {
  ApiGoalRepository(this._api);
  final ApiClient _api;

  static const _profileField = {
    'goal-study': 'daily_study_goal_minutes',
    'goal-tasks': 'daily_task_goal',
    'goal-activity': 'daily_step_goal',
    'goal-sleep': 'daily_sleep_goal_minutes',
    'goal-nutrition': 'daily_calorie_goal',
  };

  @override
  Future<List<Goal>> getGoals() async {
    final today = asMap(asMap(await _api.get('/dashboard'))['today']);
    Goal goal(String id, String title, String unit, OmniaCategory category, String current, String target) =>
        Goal(
          id: id,
          title: title,
          unit: unit,
          category: category,
          currentValue: ((today[current] as int?) ?? 0).toDouble(),
          // Goal requires a positive target; a goal of 0 means "not tracking".
          targetValue: ((today[target] as int?) ?? 0).clamp(1, 1 << 30).toDouble(),
        );
    return [
      goal('goal-study', 'Study', 'minutes', OmniaCategory.study, 'study_minutes', 'study_goal_minutes'),
      goal('goal-tasks', 'Tasks', 'tasks', OmniaCategory.tasks, 'tasks_completed', 'task_goal'),
      goal('goal-activity', 'Activity', 'steps', OmniaCategory.activity, 'steps', 'step_goal'),
      goal('goal-sleep', 'Sleep', 'minutes', OmniaCategory.sleep, 'sleep_minutes', 'sleep_goal_minutes'),
      goal('goal-nutrition', 'Food', 'kcal', OmniaCategory.nutrition, 'calories', 'calorie_goal'),
    ];
  }

  /// Only the target can change; current values come from what you log.
  @override
  Future<Goal> updateGoal(Goal goal) async {
    final field = _profileField[goal.id];
    if (field == null) throw ArgumentError.value(goal.id, 'goal.id', 'Unknown goal');
    await _api.patch('/profile', body: {field: goal.targetValue.round()});
    return goal;
  }
}
