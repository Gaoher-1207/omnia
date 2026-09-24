import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';

typedef DashboardState = Loadable<Dashboard>;

/// Which bottom tab is showing; tabs reload their data when they appear.
class TabState extends ValueNotifier<int> {
  TabState() : super(0);
}

/// State that belongs to one signed-in user. Created at sign-in and thrown
/// away at sign-out, so the next account never sees the previous one's data.
class SessionScope extends StatefulWidget {
  const SessionScope({super.key, required this.child});
  final Widget child;

  /// Refresh the numbers on Home/Track after something changed elsewhere.
  static Future<void> refreshDashboard(BuildContext context) =>
      ControllerScope.read<DashboardState>(context).load();

  @override
  State<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends State<SessionScope> {
  late final AppDependencies deps = AppDependenciesScope.of(context);
  late final tasks = TaskController(deps.tasks)..load();
  late final plan = PlanController(deps.plans);
  late final dashboard = DashboardState(deps.dashboard.load);
  final tab = TabState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      dashboard.addListener(_syncPlan);
      dashboard.load();
    });
  }

  /// The dashboard already carries today's plan; share it with the Plan tab.
  void _syncPlan() {
    final data = dashboard.data;
    if (data != null && !dashboard.loading) plan.adopt(data.plan);
  }

  @override
  void dispose() {
    dashboard.removeListener(_syncPlan);
    tasks.dispose();
    plan.dispose();
    dashboard.dispose();
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TaskScope(
    controller: tasks,
    child: ControllerScope<PlanController>(
      controller: plan,
      child: ControllerScope<DashboardState>(
        controller: dashboard,
        child: ControllerScope<TabState>(controller: tab, child: widget.child),
      ),
    ),
  );
}
