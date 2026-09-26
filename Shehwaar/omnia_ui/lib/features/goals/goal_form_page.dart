import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/choice_segments.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/goals_page.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// Create (initial == null) or edit a goal. Closes only after [onSave]
/// succeeds, so a failed save keeps the user's input.
class GoalFormPage extends StatefulWidget {
  const GoalFormPage({super.key, this.initial, required this.onSave});
  final Goal? initial;
  final Future<bool> Function(Goal goal) onSave;

  @override
  State<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends State<GoalFormPage> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late var _category = widget.initial?.category ?? OmniaCategory.study;
  late DateTime? _deadline = widget.initial?.deadline?.toLocal();
  late var _completed = widget.initial?.completed ?? false;
  late var _measurable = widget.initial?.measurable ?? true;
  late final _current = TextEditingController(
    text: _plain(widget.initial?.currentValue),
  );
  late final _target = TextEditingController(
    text: _plain(widget.initial?.targetValue),
  );
  late final _unit = TextEditingController(text: widget.initial?.unit);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _current.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  /// Editable text for a value: 12.0 → "12", 22.5 → "22.5", no grouping.
  static String? _plain(double? value) => value == null
      ? null
      : value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();

  /// Rejects "NaN" and "Infinity", which double.tryParse accepts.
  static double? _parse(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    return value != null && value.isFinite ? value : null;
  }

  static String? _validateCurrent(String? text) {
    final value = _parse(text);
    if (value == null) return 'Enter a number, like 6 or 22.5';
    return value < 0 ? 'Can’t be negative' : null;
  }

  static String? _validateTarget(String? text) {
    final value = _parse(text);
    if (value == null) return 'Enter a number, like 10 or 30';
    return value <= 0 ? 'Must be more than 0' : null;
  }

  /// The measurement the fields describe, or null while any is invalid.
  Goal? _measured() {
    final unit = _unit.text.trim();
    if (_validateCurrent(_current.text) != null ||
        _validateTarget(_target.text) != null ||
        unit.isEmpty) {
      return null;
    }
    return Goal(
      id: 'preview',
      title: 'preview',
      category: _category,
      currentValue: _parse(_current.text),
      targetValue: _parse(_target.text),
      unit: unit,
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final description = _description.text.trim();
    final measured = _measurable ? _measured() : null;
    final goal =
        (widget.initial ??
                Goal(
                  // Caller-supplied ID per GoalRepository; an API may reassign it.
                  id: 'goal-${DateTime.now().microsecondsSinceEpoch}',
                  title: _title.text.trim(),
                  category: _category,
                ))
            .copyWith(
              title: _title.text.trim(),
              description: description.isEmpty ? null : description,
              category: _category,
              deadline: _deadline,
              completed: _completed,
              // All three null makes the goal completion-only.
              currentValue: measured?.currentValue,
              targetValue: measured?.targetValue,
              unit: measured?.unit,
            );
    setState(() => _saving = true);
    final ok = await widget.onSave(goal);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the goal. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final measured = _measurable ? _measured() : null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit goal' : 'New goal')),
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
              decoration: const InputDecoration(labelText: 'Goal'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a goal' : null,
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
            SelectField<OmniaCategory>(
              label: 'Category',
              initialValue: _category,
              options: [
                for (final category in OmniaCategory.values)
                  SelectOption(category, categoryLabel(category)),
              ],
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 18),
            PickerField(
              label: 'Target date',
              value: _deadline == null ? null : formatDate(_deadline!),
              icon: Icons.event_outlined,
              onTap: _pickDeadline,
              clearTooltip: 'Clear target date',
              onClear: () => setState(() => _deadline = null),
            ),
            const SizedBox(height: 18),
            ChoiceSegments<bool>(
              label: 'Track progress',
              options: const [
                SelectOption(true, 'Measurable'),
                SelectOption(false, 'Completion only'),
              ],
              selected: _measurable,
              onChanged: (value) => setState(() => _measurable = value),
            ),
            const SizedBox(height: 18),
            if (_measurable) ...[
              TextFormField(
                controller: _current,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Current value'),
                validator: _validateCurrent,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Target value'),
                validator: _validateTarget,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unit,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'chapters, kg, books…',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a unit, like kg or books'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              // Read-only feedback: progress is always calculated.
              if (measured != null) ...[
                const SizedBox(height: 4),
                Text(
                  goalAmount(measured),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OmniaProgressBar(
                        value: measured.percent! / 100,
                        color: paper,
                        height: 10,
                        semanticsLabel: 'Calculated progress',
                      ),
                    ),
                    const SizedBox(width: 10),
                    // The progress bar already announces the percentage.
                    ExcludeSemantics(
                      child: Text(
                        '${measured.percent}%',
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
            if (editing) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Completed',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                value: _completed,
                onChanged: (value) => setState(() => _completed = value),
              ),
            ],
            const SizedBox(height: 24),
            SolidAction(
              label: _saving
                  ? 'Saving…'
                  : editing
                  ? 'Save changes'
                  : 'Add goal',
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }
}
