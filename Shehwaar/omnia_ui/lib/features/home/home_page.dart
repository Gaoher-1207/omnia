import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/plan/plan_item.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/home/widgets/agenda_line.dart';
import 'package:omnia_ui/features/home/widgets/category_card.dart';
import 'package:omnia_ui/features/home/widgets/goals_preview.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.openPlan, required this.openTrack});
  final VoidCallback openPlan;
  final VoidCallback openTrack;

  /// A failed refresh keeps the day on screen, so say why it didn't update.
  static Future<void> _refresh(
    BuildContext context,
    DashboardController controller,
  ) async {
    await controller.load();
    final error = controller.loadError;
    if (error != null && controller.dashboard != null && context.mounted) {
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = DashboardScope.of(context);
    final dashboard = controller.dashboard;
    final today = dashboard?.today;
    final sleep = today?.sleepMinutes;
    final (headline, detail) = switch ((dashboard, controller.loadError)) {
      (null, final Object error) => (
        "Couldn't load today.",
        friendlyError(error),
      ),
      (null, _) => ('Loading your day…', null),
      (Dashboard(nextExam: null), _) => (
        'No exams coming up.',
        'Upcoming exams will count down here.',
      ),
      (Dashboard(nextExam: final exam?, sample: true), _) => (
        examHeadline(exam),
        'Your plan includes a 45-minute revision session today. '
            'You can adjust it to fit your schedule.',
      ),
      (Dashboard(nextExam: final exam?), _) => (
        examHeadline(exam),
        '${exam.title}  ·  ${formatLongDate(exam.date)}',
      ),
    };
    return RefreshIndicator(
      onRefresh: () => _refresh(context, controller),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    dashboard == null
                        ? 'Hello.'
                        : 'Good ${dashboard.greeting},\n${dashboard.displayName}.',
                    style: TextStyle(
                      fontSize: 29,
                      height: 1.04,
                      fontWeight: FontWeight.w900,
                      color: context.foreground,
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Settings',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                icon: const Icon(Icons.settings_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: context.actionBackground,
                  foregroundColor: context.actionForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            switch (dashboard) {
              null => controller.loading ? 'Loading today…' : '',
              Dashboard(sample: true) =>
                '${formatLongDate(dashboard.date)}  ·  SAMPLE DAY',
              _ => formatLongDate(dashboard.date),
            },
            style: TextStyle(
              fontSize: 12,
              letterSpacing: .4,
              color: context.foreground,
            ),
          ),
          const SizedBox(height: 18),
          HardCard(
            color: lilac,
            prominent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OmniaMark(),
                    SizedBox(width: 9),
                    // Unchanged at normal sizes; only shrinks to make room for
                    // the tag at large accessibility text sizes.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'omnia',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    if (dashboard?.sample ?? false) ...[
                      SizedBox(width: 8),
                      LabelTag(text: 'SAMPLE'),
                    ],
                  ],
                ),
                const SizedBox(height: 17),
                Text(
                  headline,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(detail, style: TextStyle(height: 1.35)),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (dashboard == null && controller.loadError != null)
                      Expanded(
                        child: SolidAction(
                          label: 'Try again',
                          onTap: controller.load,
                        ),
                      )
                    else ...[
                      Expanded(
                        child: SolidAction(
                          label: "View today's plan",
                          onTap: openPlan,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => showInfoDialog(
                          context,
                          'Sample recommendation',
                          'This sample plan includes 45 minutes of revision for the DBMS exam in 8 days. Personalized recommendations are coming soon.',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cardForeground(
                            lilac,
                            prominent: true,
                          ),
                          side: BorderSide(
                            color: context.foreground,
                            width: 1.5,
                          ),
                        ),
                        child: Text('Why?'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CategoryCard(
                  icon: Icons.menu_book_outlined,
                  title: 'Study',
                  amount: today == null
                      ? '—'
                      : formatMinutes(today.studyMinutes),
                  goal: today == null
                      ? ''
                      : '/ ${formatMinutes(today.studyGoalMinutes)}',
                  progress: today == null
                      ? 0
                      : towards(today.studyMinutes, today.studyGoalMinutes),
                  color: blue,
                  onTap: openTrack,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final tasks = TaskScope.of(context);
                    final total = tasks.tasks.length;
                    final done = tasks.completedCount;
                    return CategoryCard(
                      icon: Icons.task_alt,
                      title: 'Tasks',
                      amount: '$done / $total',
                      goal: 'completed',
                      progress: total == 0 ? 0 : done / total,
                      color: yellow,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => const TasksPage()),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CategoryCard(
                  icon: Icons.directions_run,
                  title: 'Activity',
                  amount: today == null ? '—' : formatCount(today.steps),
                  goal: today == null ? '' : '/ ${formatCount(today.stepGoal)}',
                  progress: today == null
                      ? 0
                      : towards(today.steps, today.stepGoal),
                  color: mint,
                  onTap: openTrack,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: CategoryCard(
                  icon: Icons.dark_mode_outlined,
                  title: 'Sleep',
                  amount: today == null
                      ? '—'
                      : sleep == null
                      ? 'Not logged'
                      : formatMinutes(sleep),
                  goal: today == null
                      ? ''
                      : '/ ${formatMinutes(today.sleepGoalMinutes)}',
                  progress: today == null || sleep == null
                      ? 0
                      : towards(sleep, today.sleepGoalMinutes),
                  color: lilac,
                  onTap: openTrack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const GoalsPreview(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      text: 'Next up',
                      children: [
                        // Still the sample plan: say so once the rest of
                        // Home is real. Inline, so large text wraps it.
                        if (dashboard?.sample != true)
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: LabelTag(text: 'SAMPLE'),
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              TextButton(
                onPressed: openPlan,
                child: Text('See all →', semanticsLabel: 'See all'),
              ),
            ],
          ),
          AgendaLine(
            onTap: () => openPlanItem(context, samplePlan[2]),
            time: '10:00',
            title: RevisionScope.of(context).title,
            duration: '45m',
            icon: Icons.menu_book_outlined,
            color: blue,
          ),
          AgendaLine(
            onTap: () => openPlanItem(context, samplePlan[3]),
            time: '11:00',
            title: 'Complete Assignment',
            duration: '1h',
            icon: Icons.task_alt,
            color: yellow,
          ),
          AgendaLine(
            onTap: () => openPlanItem(context, samplePlan[5]),
            time: '16:30',
            title: 'Walk',
            duration: '20m',
            icon: Icons.directions_walk,
            color: mint,
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}
