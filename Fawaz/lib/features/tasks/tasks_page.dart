import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/task_form_page.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  static void _failed(BuildContext context, String action) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not $action the task. Try again.')),
      );

  static void _openForm(
    BuildContext context,
    TaskController tasks, [
    Task? task,
  ]) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => TaskFormPage(
        initial: task,
        onSave: task == null ? tasks.create : tasks.update,
      ),
    ),
  );

  static Future<void> _delete(
    BuildContext context,
    TaskController tasks,
    Task task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${task.title}” will be removed.'),
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
    if (!await tasks.delete(task.id) && context.mounted) {
      _failed(context, 'delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = TaskScope.of(context);
    final items = tasks.tasks;
    final Widget body;
    if (!tasks.loaded && tasks.loadError == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!tasks.loaded) {
      body = _Message(
        title: 'Tasks could not be loaded',
        action: SolidAction(label: 'Try again', onTap: tasks.load),
      );
    } else if (items.isEmpty) {
      body = const _Message(
        title: 'No tasks yet',
        detail: 'Add your first task to start planning your day.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          Text(
            '${tasks.completedCount} of ${items.length} completed',
            style: TextStyle(color: context.mutedForeground),
          ),
          const SizedBox(height: 12),
          for (final task in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(
                key: ValueKey(task.id),
                task: task,
                busy: tasks.isBusy(task.id),
                onToggle: (value) async {
                  if (!await tasks.setCompleted(task.id, value) &&
                      context.mounted) {
                    _failed(context, 'update');
                  }
                },
                onEdit: () => _openForm(context, tasks, task),
                onDelete: () => _delete(context, tasks, task),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: const Text(
          'Tasks',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: tasks.loading ? null : tasks.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, tasks),
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add task',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final Task task;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = [
      '${priorityLabel(task.priority)} priority',
      categoryLabel(task.category),
      if (task.dueAt != null) 'Due ${formatDue(task.dueAt!)}',
      if (task.estimatedDuration != null)
        formatDuration(task.estimatedDuration!),
    ];
    return HardCard(
      shadowOffset: const Offset(2, 3),
      color: task.completed ? paper : yellow,
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: task.completed,
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
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      decoration: task.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (task.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      task.description!,
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
            tooltip: 'Task actions',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(value: onEdit, child: const Text('Edit')),
              PopupMenuItem(value: onDelete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
