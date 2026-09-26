import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';
import 'package:omnia_ui/features/home/data/api_dashboard_repository.dart';
import 'package:omnia_ui/features/home/data/mock_dashboard_repository.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';
import 'package:omnia_ui/features/track/data/api_track_repository.dart';
import 'package:omnia_ui/features/track/data/mock_track_repository.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';

/// The composition boundary. API adapters can be injected here later.
/// initialRevisionSession must be a session already loaded from [study].
class AppDependencies {
  const AppDependencies({
    required this.tasks, required this.goals, required this.study,
    required this.dashboard, required this.track,
    required this.initialRevisionSession,
    this.sampleContent = false,
  });

  factory AppDependencies.mock() {
    final revision = MockData.revisionSession;
    // One in-memory day for both: a mock log shows on the mock dashboard.
    final track = MockTrackRepository();
    return AppDependencies(
      tasks: MockTaskRepository(), goals: MockGoalRepository(),
      study: MockStudyRepository(sessions: [revision]),
      dashboard: MockDashboardRepository(track: track), track: track,
      initialRevisionSession: revision, sampleContent: true,
    );
  }

  /// API mode: tasks, the dashboard, activity and sleep come from the
  /// backend. Goals stay in-memory until their own integration phase, and
  /// start empty: the user's, never the demo's. Study is still the demo
  /// session, which screens hide while [sampleContent] is false.
  factory AppDependencies.api(ApiClient api) {
    final local = AppDependencies.mock();
    return AppDependencies(
      tasks: ApiTaskRepository(api), goals: MockGoalRepository(seed: const []),
      study: local.study,
      dashboard: ApiDashboardRepository(api), track: ApiTrackRepository(api),
      initialRevisionSession: local.initialRevisionSession,
    );
  }

  final TaskRepository tasks;
  final GoalRepository goals;
  final StudyRepository study;
  final DashboardRepository dashboard;
  final TrackRepository track;
  final StudySession initialRevisionSession;

  /// Mock mode's demo day: the sample plan, revision session and "Why?"
  /// exist only here. Real sessions show real data or an empty state.
  final bool sampleContent;
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
