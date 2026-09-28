import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/features/assistant/assistant_controller.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/track/track_controller.dart';

/// State that belongs to one user. In API mode it is keyed by the signed-in
/// user, so signing out (or in as someone else) disposes it and the next
/// account starts clean. In mock mode there is one session for the app's life.
class UserSession extends StatefulWidget {
  const UserSession({
    super.key,
    required this.dependencies,
    required this.child,
  });

  /// Builds this session's feature repositories, once, when it starts.
  final AppDependencies Function() dependencies;
  final Widget child;

  @override
  State<UserSession> createState() => _UserSessionState();
}

class _UserSessionState extends State<UserSession> {
  late final dependencies = widget.dependencies();
  late final revision = RevisionController(
    session: dependencies.initialRevisionSession,
    repository: dependencies.revision,
  );
  late final plan = PlanController(dependencies.plan, loadsWithDashboard: true);
  late final commitments = CommitmentController(dependencies.commitments);
  late final tasks = TaskController(dependencies.tasks)..load();
  late final goals = GoalController(dependencies.goals)..load();
  late final dashboard = DashboardController(dependencies.dashboard);
  Dashboard? _syncedDashboard;
  late final track = TrackController(dependencies.track, dashboard);
  // Loaded when Study opens, not at sign-in.
  late final study = StudyController(dependencies.study, dashboard);
  // Held only in memory: a new session starts a new conversation.
  late final assistant = AssistantController(dependencies.assistant);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    dashboard.addListener(_syncTodayPlan);
    dashboard.load();
    // The day may have changed while the app was in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        dashboard.load();
        if (plan.selectedDate != null) plan.load();
      },
    );
  }

  void _syncTodayPlan() {
    final result = dashboard.dashboard;
    if (result == null && dashboard.loadError != null) {
      plan.seedTodayError(dashboard.loadError!);
    }
    if (result == null || identical(result, _syncedDashboard)) return;
    _syncedDashboard = result;
    plan.seedToday(result.date, result.aiPlan);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    dashboard.removeListener(_syncTodayPlan);
    plan.dispose();
    commitments.dispose();
    revision.dispose();
    tasks.dispose();
    goals.dispose();
    track.dispose();
    study.dispose();
    assistant.dispose();
    dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDependenciesScope(
    dependencies: dependencies,
    child: RevisionScope(
      controller: revision,
      child: TaskScope(
        controller: tasks,
        child: GoalScope(
          controller: goals,
          child: DashboardScope(
            controller: dashboard,
            child: TrackScope(
              controller: track,
              child: StudyScope(
                controller: study,
                child: AssistantScope(
                  controller: assistant,
                  child: PlanScope(
                    controller: plan,
                    child: CommitmentScope(
                      controller: commitments,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
