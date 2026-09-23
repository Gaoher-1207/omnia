import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';

class PlanItem {
  const PlanItem(
    this.time,
    this.title,
    this.duration,
    this.icon,
    this.color, {
    this.isRevision = false,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  final bool isRevision;

  String displayTitle(BuildContext context) =>
      isRevision ? RevisionScope.of(context).title : title;
}

const samplePlan = [
  PlanItem('08:00', 'Morning Routine', '30m', Icons.dark_mode_outlined, lilac),
  PlanItem('09:00', 'College / Classes', '1h', Icons.school_outlined, yellow),
  PlanItem(
    '10:00',
    'DBMS Revision',
    '45m',
    Icons.menu_book_outlined,
    blue,
    isRevision: true,
  ),
  PlanItem('11:00', 'Complete Assignment', '1h', Icons.task_alt, yellow),
  PlanItem('13:00', 'Lunch', '1h', Icons.restaurant_outlined, mint),
  PlanItem('16:30', 'Walk', '20m', Icons.directions_walk, mint),
  PlanItem('18:30', 'Push Workout', '35m', Icons.fitness_center, mint),
  PlanItem('21:00', 'Revision', '45m', Icons.menu_book_outlined, blue),
  PlanItem('22:00', 'Wind Down', '30m', Icons.dark_mode_outlined, lilac),
];

void openPlanItem(BuildContext context, PlanItem item) {
  if (item.isRevision) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const RevisionDetailPage()),
    );
  } else {
    showInfoDialog(
      context,
      item.title,
      '${item.time} · ${item.duration}\nThis is a sample plan item. Editing and scheduling other activities are coming soon.',
    );
  }
}
