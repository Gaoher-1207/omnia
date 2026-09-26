import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/assistant/data/api_assistant_repository.dart';
import 'package:omnia_ui/features/assistant/data/mock_assistant_repository.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';
import 'package:omnia_ui/features/goals/data/mock_goal_repository.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';
import 'package:omnia_ui/features/home/data/api_dashboard_repository.dart';
import 'package:omnia_ui/features/home/data/mock_dashboard_repository.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';
import 'package:omnia_ui/features/study/data/api_study_repository.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/study/domain/revision_repository.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';
import 'package:omnia_ui/features/track/data/api_track_repository.dart';
import 'package:omnia_ui/features/track/data/mock_track_repository.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';

/// The composition boundary. API adapters can be injected here later.
/// initialRevisionSession must be a session already loaded from [revision].
class AppDependencies {
  const AppDependencies({
    required this.tasks, required this.goals, required this.study,
    required this.dashboard, required this.track, required this.revision,
    required this.assistant, required this.initialRevisionSession,
    this.sampleContent = false,
  });

  factory AppDependencies.mock() {
    final revision = MockData.revisionSession;
    // One in-memory day for all three: a mock log or exam shows on the
    // mock dashboard.
    final track = MockTrackRepository();
    final study = MockStudyRepository(sessions: [revision]);
    return AppDependencies(
      tasks: MockTaskRepository(), goals: MockGoalRepository(),
      study: study, revision: study,
      dashboard: MockDashboardRepository(track: track, study: study),
      track: track, assistant: MockAssistantRepository(),
      initialRevisionSession: revision, sampleContent: true,
    );
  }

  /// API mode: tasks, the dashboard, activity, sleep, study subjects and
  /// exams, and Ask Omnia's answers come from the backend. Goals stay
  /// in-memory until their own integration phase, and start empty: the
  /// user's, never the demo's. The
  /// demo revision session has no backend twin; screens hide it while
  /// [sampleContent] is false.
  factory AppDependencies.api(ApiClient api) {
    final local = AppDependencies.mock();
    return AppDependencies(
      tasks: ApiTaskRepository(api), goals: MockGoalRepository(seed: const []),
      study: ApiStudyRepository(api), revision: local.revision,
      dashboard: ApiDashboardRepository(api), track: ApiTrackRepository(api),
      assistant: ApiAssistantRepository(api),
      initialRevisionSession: local.initialRevisionSession,
    );
  }

  final TaskRepository tasks;
  final GoalRepository goals;
  final StudyRepository study;
  final RevisionRepository revision;
  final DashboardRepository dashboard;
  final TrackRepository track;
  final AssistantRepository assistant;
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
