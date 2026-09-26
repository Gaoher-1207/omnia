import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
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
  late final tasks = TaskController(dependencies.tasks)..load();
  late final goals = GoalController(dependencies.goals)..load();
  late final dashboard = DashboardController(dependencies.dashboard)..load();
  late final track = TrackController(dependencies.track, dashboard);
  // Loaded when Study opens, not at sign-in.
  late final study = StudyController(dependencies.study, dashboard);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The day may have changed while the app was in the background.
    _lifecycle = AppLifecycleListener(onResume: dashboard.load);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    revision.dispose();
    tasks.dispose();
    goals.dispose();
    track.dispose();
    study.dispose();
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
              child: StudyScope(controller: study, child: widget.child),
            ),
          ),
        ),
      ),
    ),
  );
}
