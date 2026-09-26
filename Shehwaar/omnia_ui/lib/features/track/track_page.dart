import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/features/track/activity_log_page.dart';
import 'package:omnia_ui/features/track/sleep_log_page.dart';
import 'package:omnia_ui/features/track/widgets/activity_line.dart';
import 'package:omnia_ui/features/track/widgets/track_tile.dart';

class TrackPage extends StatelessWidget {
  const TrackPage({super.key});
  @override
  Widget build(BuildContext context) {
    // The same dashboard Home shows; no second request.
    final dashboard = DashboardScope.of(context).dashboard;
    final today = dashboard?.today;
    final sleep = today?.sleepMinutes;
    final sample = dashboard?.sample ?? false;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Track',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
          ),
        ),
        SizedBox(height: 4),
        Text(
          sample
              ? 'Your day at a glance  ·  SAMPLE DATA'
              : 'Your day at a glance',
        ),
        SizedBox(height: 20),
        TrackTile(
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
        ),
        _TasksTile(),
        TrackTile(
          icon: Icons.directions_walk,
          name: 'Activity',
          amount: today == null ? '—' : formatCount(today.steps),
          goal: today == null ? '' : '${formatCount(today.stepGoal)} steps',
          progress: today == null ? 0 : towards(today.steps, today.stepGoal),
          color: mint,
          onTap: () => ActivityLogPage.open(context),
        ),
        TrackTile(
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
        SizedBox(height: 15),
        Row(
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  'Today’s activity',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            // Still sample rows: say so once the tiles above are real.
            if (!sample) ...[SizedBox(width: 8), LabelTag(text: 'SAMPLE')],
          ],
        ),
        SizedBox(height: 9),
        HardCard(
          color: paper,
          child: Column(
            children: [
              ActivityLine(
                icon: Icons.check,
                title: 'Morning routine',
                time: '08:30',
              ),
              Divider(),
              ActivityLine(
                icon: Icons.menu_book_outlined,
                title: 'DBMS study',
                time: '10:00',
              ),
              Divider(),
              ActivityLine(
                icon: Icons.directions_walk,
                title: 'Walk',
                time: '16:30',
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }
}

/// Live counts from the app-level TaskController, the same source as Home.
class _TasksTile extends StatelessWidget {
  const _TasksTile();
  @override
  Widget build(BuildContext context) {
    final tasks = TaskScope.of(context);
    final total = tasks.tasks.length;
    final done = tasks.completedCount;
    return TrackTile(
      icon: Icons.task_alt,
      name: 'Tasks',
      amount: '$done of $total',
      goal: 'tasks done',
      progress: total == 0 ? 0 : done / total,
      color: yellow,
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const TasksPage()),
      ),
    );
  }
}
