import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';

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
    repository: dependencies.study,
  );
  late final tasks = TaskController(dependencies.tasks)..load();
  late final goals = GoalController(dependencies.goals)..load();

  @override
  void dispose() {
    revision.dispose();
    tasks.dispose();
    goals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDependenciesScope(
    dependencies: dependencies,
    child: RevisionScope(
      controller: revision,
      child: TaskScope(
        controller: tasks,
        child: GoalScope(controller: goals, child: widget.child),
      ),
    ),
  );
}
