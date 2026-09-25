import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';

/// The composition boundary. API adapters can be injected here later.
/// initialRevisionSession must be a session already loaded from [study].
class AppDependencies {
  const AppDependencies({
    required this.tasks, required this.goals, required this.study,
    required this.initialRevisionSession,
  });

  factory AppDependencies.mock() {
    final revision = MockData.revisionSession;
    return AppDependencies(
      tasks: MockTaskRepository(), goals: MockGoalRepository(),
      study: MockStudyRepository(sessions: [revision]),
      initialRevisionSession: revision,
    );
  }

  /// API mode: tasks live on the backend; the other features stay in-memory
  /// until their own integration phase.
  factory AppDependencies.api(ApiClient api) {
    final local = AppDependencies.mock();
    return AppDependencies(
      tasks: ApiTaskRepository(api), goals: local.goals, study: local.study,
      initialRevisionSession: local.initialRevisionSession,
    );
  }

  final TaskRepository tasks;
  final GoalRepository goals;
  final StudyRepository study;
  final StudySession initialRevisionSession;
}

class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key, required this.dependencies, required super.child,
  });
  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDependenciesScope>()!.dependencies;

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
