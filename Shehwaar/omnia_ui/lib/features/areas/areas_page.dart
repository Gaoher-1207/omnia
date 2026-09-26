import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/areas/widgets/area_tile.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/goals/goals_page.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/study/study_page.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/features/track/activity_log_page.dart';
import 'package:omnia_ui/features/track/sleep_log_page.dart';

/// The parts of life OMNIA manages. Each tile shows only what its
/// controller really knows, and opens that area.
class AreasPage extends StatelessWidget {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The same dashboard Today shows; no second request.
    final dashboard = DashboardScope.of(context).dashboard;
    final today = dashboard?.today;
    final sleep = today?.sleepMinutes;
    final tasks = TaskScope.of(context), goals = GoalScope.of(context);
    return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Areas',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dashboard?.sample ?? false
                ? 'Everything you manage  ·  SAMPLE DATA'
                : 'Everything you manage',
            style: TextStyle(color: context.mutedForeground),
          ),
          const SizedBox(height: 20),
          AreaTile(
            icon: Icons.menu_book_outlined,
            name: 'Study',
            amount: today == null ? '—' : formatMinutes(today.studyMinutes),
            goal: today == null
                ? ''
                : '${formatMinutes(today.studyGoalMinutes)} goal',
            progress: today == null
                ? 0
                : towards(today.studyMinutes, today.studyGoalMinutes),
            color: blue,
            onTap: () => StudyPage.open(context),
          ),
          AreaTile(
            icon: Icons.task_alt,
            name: 'Tasks',
            amount: tasks.loaded
                ? '${tasks.completedCount} of ${tasks.tasks.length}'
                : '—',
            goal: 'tasks done',
            progress: !tasks.loaded || tasks.tasks.isEmpty
                ? 0
                : tasks.completedCount / tasks.tasks.length,
            color: yellow,
            onTap: () => TasksPage.open(context),
          ),
          AreaTile(
            icon: Icons.flag_outlined,
            name: 'Goals',
            amount: goals.loaded ? '${goals.active.length} active' : '—',
            goal: goals.loaded ? '${goals.completed.length} completed' : '',
            color: paper,
            onTap: () => GoalsPage.open(context),
          ),
          AreaTile(
            icon: Icons.directions_walk,
            name: 'Activity',
            amount: today == null ? '—' : formatCount(today.steps),
            goal: today == null ? '' : '${formatCount(today.stepGoal)} steps',
            progress: today == null ? 0 : towards(today.steps, today.stepGoal),
            color: mint,
            onTap: () => ActivityLogPage.open(context),
          ),
          AreaTile(
            icon: Icons.dark_mode_outlined,
            name: 'Sleep',
            amount: today == null
                ? '—'
                : sleep == null
                ? 'Not logged'
                : formatMinutes(sleep),
            goal: today == null
                ? ''
                : '${formatMinutes(today.sleepGoalMinutes)} goal',
            progress: today == null || sleep == null
                ? 0
                : towards(sleep, today.sleepGoalMinutes),
            color: lilac,
            onTap: () => SleepLogPage.open(context),
          ),
      ],
    );
  }
}
