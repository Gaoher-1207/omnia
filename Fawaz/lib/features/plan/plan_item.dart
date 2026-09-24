import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';

/// Colour family and icon for each kind of plan item, matching the cards.
({IconData icon, Color color}) planStyle(DailyPlanItem item) => switch (item.category) {
  PlanCategory.study => (icon: Icons.menu_book_outlined, color: blue),
  PlanCategory.task => (icon: Icons.task_alt, color: yellow),
  PlanCategory.fitness => (icon: Icons.directions_run, color: mint),
  PlanCategory.recovery => (
    icon: item.isBreak ? Icons.restaurant_outlined : Icons.dark_mode_outlined,
    color: lilac,
  ),
  PlanCategory.other => (icon: Icons.circle_outlined, color: paper),
};

/// Study items open the revision session for their subject, task items open
/// Tasks, and everything else shows its details.
void openPlanItem(BuildContext context, DailyPlanItem item) {
  if (item.category == PlanCategory.study) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => RevisionDetailPage(item: item)),
    );
  } else if (item.category == PlanCategory.task) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const TasksPage()),
    );
  } else {
    showInfoDialog(
      context,
      item.title,
      [
        '${item.start} – ${item.end} · ${formatMinutes(item.minutes)}',
        if (item.detail != null) item.detail!,
      ].join('\n'),
    );
  }
}
