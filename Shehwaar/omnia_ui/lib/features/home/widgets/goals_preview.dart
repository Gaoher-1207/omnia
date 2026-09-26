import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/accent_circle.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/goals/goals_page.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// The two most pressing active goals, read from the shared [GoalController].
class GoalsPreview extends StatelessWidget {
  const GoalsPreview({super.key});

  static void _open(BuildContext context) => GoalsPage.open(context);

  @override
  Widget build(BuildContext context) {
    final goals = GoalScope.of(context);
    final next = goals.active.take(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: const Text(
                  'Goals',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _open(context),
              child: const Text('See all →', semanticsLabel: 'See all goals'),
            ),
          ],
        ),
        if (goals.loaded && next.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HardCard(
              color: paper,
              shadowOffset: const Offset(2, 3),
              onTap: () => _open(context),
              child: const Text('No active goals. Add one to work toward.'),
            ),
          ),
        for (final goal in next)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HardCard(
              color: paper,
              shadowOffset: const Offset(2, 3),
              onTap: () => _open(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AccentCircle(
                        color: categoryStyle(goal.category).$1,
                        size: 28,
                        icon: categoryStyle(goal.category).$2,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          goal.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (goal.measurable) ...[
                    // The progress bar announces the percentage.
                    Text(
                      '${goalAmount(goal)}  ·  ${goal.percent}%',
                      semanticsLabel: goalAmount(goal),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    OmniaProgressBar(
                      value: goal.percent! / 100,
                      color: paper,
                      semanticsLabel: '${goal.title} progress',
                    ),
                  ] else
                    Text(
                      [
                        'Active',
                        if (goal.deadline != null)
                          'By ${formatDate(goal.deadline!.toLocal())}',
                      ].join('  ·  '),
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
