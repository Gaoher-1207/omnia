import 'package:flutter/material.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// Create (initial == null) or edit a task. Closes only after [onSave]
/// succeeds, so a failed save keeps the user's input.
class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key, this.initial, required this.onSave});
  final Task? initial;
  final Future<bool> Function(Task task) onSave;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _minutes = TextEditingController(
    text: widget.initial?.estimatedDuration?.inMinutes.toString(),
  );
  late var _priority = widget.initial?.priority ?? TaskPriority.normal;
  late var _category = widget.initial?.category ?? OmniaCategory.tasks;
  late DateTime? _date = widget.initial?.dueAt?.toLocal();
  late TimeOfDay? _time = _date == null || isAllDay(_date!)
      ? null
      : TimeOfDay.fromDateTime(_date!);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  static String? _validateMinutes(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final minutes = int.tryParse(text);
    if (minutes == null || minutes < 1 || minutes > 24 * 60) {
      return 'Enter whole minutes from 1 to 1440';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final date = _date;
    final dueAt = date == null
        ? null
        : DateTime(
            date.year,
            date.month,
            date.day,
            _time?.hour ?? 0,
            _time?.minute ?? 0,
          );
    final minutes = int.tryParse(_minutes.text.trim());
    final description = _description.text.trim();
    final initial = widget.initial;
    final task = initial == null
        ? Task(
            // Caller-supplied ID per TaskRepository; an API may reassign it.
            id: 'task-${DateTime.now().microsecondsSinceEpoch}',
            createdAt: DateTime.now(),
            title: _title.text.trim(),
          )
        : initial.copyWith(title: _title.text.trim());
    final result = task.copyWith(
      description: description.isEmpty ? null : description,
      priority: _priority,
      category: _category,
      dueAt: dueAt,
      estimatedDuration: minutes == null ? null : Duration(minutes: minutes),
    );
    setState(() => _saving = true);
    final ok = await widget.onSave(result);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the task. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit task' : 'New task')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: _title,
              autofocus: !editing,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a title'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            _label('Priority'),
            SegmentedButton<TaskPriority>(
              segments: [
                for (final priority in TaskPriority.values)
                  ButtonSegment(
                    value: priority,
                    label: Text(priorityLabel(priority)),
                  ),
              ],
              selected: {_priority},
              onSelectionChanged: (selection) =>
                  setState(() => _priority = selection.single),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<OmniaCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in OmniaCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(categoryLabel(category)),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 18),
            _label('Due'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_date == null ? 'Add date' : formatDate(_date!)),
                ),
                if (_date != null)
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _time == null ? 'Add time' : _time!.format(context),
                    ),
                  ),
                if (_date != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() {
                      _date = null;
                      _time = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimated minutes (optional)',
              ),
              validator: _validateMinutes,
            ),
            const SizedBox(height: 24),
            SolidAction(
              label: _saving
                  ? 'Saving…'
                  : editing
                  ? 'Save changes'
                  : 'Add task',
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}
