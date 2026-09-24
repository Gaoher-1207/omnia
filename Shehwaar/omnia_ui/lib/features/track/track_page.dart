import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/track/widgets/activity_line.dart';
import 'package:omnia_ui/features/track/widgets/track_tile.dart';

class TrackPage extends StatelessWidget {
  const TrackPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
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
      Text('Your day at a glance  ·  SAMPLE DATA'),
      SizedBox(height: 20),
      TrackTile(
        icon: Icons.menu_book_outlined,
        name: 'Study',
        amount: '2h 15m',
        goal: '4h goal',
        progress: .56,
        color: blue,
      ),
      _TasksTile(),
      TrackTile(
        icon: Icons.directions_walk,
        name: 'Activity',
        amount: '6,240',
        goal: '8,000 steps',
        progress: .78,
        color: mint,
      ),
      TrackTile(
        icon: Icons.dark_mode_outlined,
        name: 'Sleep',
        amount: '6h 42m',
        goal: '8h goal',
        progress: .84,
        color: lilac,
      ),
      SizedBox(height: 15),
      Semantics(
        header: true,
        child: Text(
          'Today’s activity',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
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
    );
  }
}
