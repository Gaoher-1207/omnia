import 'package:flutter/material.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/goals/goal_form_page.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// The OMNIA accent family and icon for a category. Only four accents exist,
/// so nutrition and habits share one; the label always names the category.
(Color, IconData) categoryStyle(OmniaCategory category) => switch (category) {
  OmniaCategory.study => (blue, Icons.menu_book_outlined),
  OmniaCategory.tasks => (yellow, Icons.task_alt),
  OmniaCategory.activity => (mint, Icons.directions_run),
  OmniaCategory.sleep => (lilac, Icons.dark_mode_outlined),
  OmniaCategory.nutrition => (yellow, Icons.restaurant_outlined),
  OmniaCategory.habits => (lilac, Icons.repeat),
};

/// 18000 → "18,000", 22.5 → "22.5", 12.0 → "12" (at most two decimals).
String formatAmount(double value) {
  final [whole, ...fraction] = value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .split('.');
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  return [grouped, ...fraction].join('.');
}

/// "22.5 / 30 kg" for a measurable goal.
String goalAmount(Goal goal) =>
    '${formatAmount(goal.currentValue!)} / '
    '${formatAmount(goal.targetValue!)} ${goal.unit}';

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  static void _failed(BuildContext context, String action) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not $action the goal. Try again.')),
      );

  static void _openForm(
    BuildContext context,
    GoalController goals, [
    Goal? goal,
  ]) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => GoalFormPage(
        initial: goal,
        onSave: goal == null ? goals.create : goals.update,
      ),
    ),
  );

  static Future<void> _delete(
    BuildContext context,
    GoalController goals,
    Goal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('“${goal.title}” and its progress will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (!await goals.delete(goal.id) && context.mounted) {
      _failed(context, 'delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = GoalScope.of(context);
    final active = goals.active, completed = goals.completed;
    Widget card(Goal goal) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _GoalCard(
        key: ValueKey(goal.id),
        goal: goal,
        busy: goals.isBusy(goal.id),
        onToggle: (value) async {
          if (!await goals.setCompleted(goal.id, value) && context.mounted) {
            _failed(context, 'update');
          }
        },
        onEdit: () => _openForm(context, goals, goal),
        onDelete: () => _delete(context, goals, goal),
      ),
    );
    final Widget body;
    if (!goals.loaded && goals.loadError == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!goals.loaded) {
      body = _Message(
        title: 'Goals could not be loaded',
        action: SolidAction(label: 'Try again', onTap: goals.load),
      );
    } else if (goals.isEmpty) {
      body = const _Message(
        title: 'No goals yet',
        detail:
            'Add something you are working toward, like finishing a '
            'syllabus or reading 12 books.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          Text(
            '${active.length} active  ·  ${completed.length} completed',
            style: TextStyle(color: context.mutedForeground),
          ),
          const SizedBox(height: 12),
          const _Header('Active'),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Every goal is done. Add a new one when you’re ready.',
              ),
            ),
          for (final goal in active) card(goal),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _Header('Completed'),
            for (final goal in completed) card(goal),
          ],
        ],
      );
    }
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: const Text(
          'Goals',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: goals.loading ? null : goals.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, goals),
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add goal',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    super.key,
    required this.goal,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final Goal goal;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final deadline = goal.deadline?.toLocal();
    final meta = [
      categoryLabel(goal.category),
      if (deadline != null) 'By ${formatDate(deadline)}',
    ];
    final color = goal.completed ? paper : categoryStyle(goal.category).$1;
    return HardCard(
      shadowOffset: const Offset(2, 3),
      color: color,
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: goal.completed,
                semanticLabel: goal.title,
                // Same contrast fix as the task card's checkbox.
                side: BorderSide(
                  color: context.cardForeground(color),
                  width: 2,
                ),
                onChanged: busy ? null : (value) => onToggle(value ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          decoration: goal.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (goal.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          goal.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        meta.join('  ·  '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: 'Goal actions',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: onEdit, child: const Text('Edit')),
                  PopupMenuItem(
                    value: () => onToggle(!goal.completed),
                    enabled: !busy,
                    child: Text(goal.completed ? 'Reopen' : 'Mark complete'),
                  ),
                  PopupMenuItem(value: onDelete, child: const Text('Delete')),
                ],
              ),
            ],
          ),
          if (goal.measurable) ...[
            const SizedBox(height: 8),
            Text(
              goalAmount(goal),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OmniaProgressBar(
                    value: goal.percent! / 100,
                    color: color,
                    height: 10,
                    semanticsLabel: '${goal.title} progress',
                  ),
                ),
                const SizedBox(width: 10),
                // The progress bar already announces the percentage.
                ExcludeSemantics(
                  child: Text(
                    '${goal.percent}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
