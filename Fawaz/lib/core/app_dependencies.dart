import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/features/goals/data/api_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';
import 'package:omnia_ui/features/home/data/dashboard_repository.dart';
import 'package:omnia_ui/features/insights/data/progress_repository.dart';
import 'package:omnia_ui/features/plan/data/plan_repository.dart';
import 'package:omnia_ui/features/social/data/social_repository.dart';
import 'package:omnia_ui/features/study/data/api_study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';
import 'package:omnia_ui/features/track/data/track_repository.dart';

/// The composition boundary: every screen gets its data through these
/// repositories, which all talk to the backend through one [ApiClient].
class AppDependencies {
  AppDependencies({
    required this.api,
    required this.tasks,
    required this.goals,
    required this.study,
    required this.dashboard,
    required this.plans,
    required this.progress,
    required this.track,
    required this.social,
  });

  factory AppDependencies.forApi(ApiClient api) => AppDependencies(
    api: api,
    tasks: ApiTaskRepository(api),
    goals: ApiGoalRepository(api),
    study: ApiStudyRepository(api),
    dashboard: DashboardRepository(api),
    plans: PlanRepository(api),
    progress: ProgressRepository(api),
    track: TrackRepository(api),
    social: SocialRepository(api),
  );

  /// Production wiring: secure token storage + the configured base URL.
  factory AppDependencies.production(String baseUrl) =>
      AppDependencies.forApi(ApiClient(baseUrl: baseUrl, tokens: SecureTokenStore()));

  final ApiClient api;
  final TaskRepository tasks;
  final GoalRepository goals;
  final StudyRepository study;
  final DashboardRepository dashboard;
  final PlanRepository plans;
  final ProgressRepository progress;
  final TrackRepository track;
  final SocialRepository social;
}

class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });
  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDependenciesScope>()!.dependencies;

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
