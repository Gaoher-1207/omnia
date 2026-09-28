import 'package:flutter/material.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_time.dart';

class CommitmentFormPage extends StatefulWidget {
  const CommitmentFormPage({
    super.key,
    this.initial,
    this.initialKind = 'recurring',
  });
  final Commitment? initial;
  final String initialKind;

  @override
  State<CommitmentFormPage> createState() => _CommitmentFormPageState();
}

class _CommitmentFormPageState extends State<CommitmentFormPage> {
  static const categories = [
    'college',
    'work',
    'class',
    'coaching',
    'commute',
    'appointment',
    'other',
  ];
  static const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  late final _title = TextEditingController(
    text:
        widget.initial?.title ??
        (widget.initialKind == 'one_off' ? 'Appointment' : 'College'),
  );
  late String _category =
      widget.initial?.category ??
      (widget.initialKind == 'one_off' ? 'appointment' : 'college');
  late String _kind = widget.initial?.kind ?? widget.initialKind;
  late final _weekdays =
      widget.initial?.weekdays.toSet() ?? <int>{0, 1, 2, 3, 4};
  late DateTime? _day = widget.initial?.day;
  late int _start = widget.initial?.startMinutes ?? 9 * 60,
      _end = widget.initial?.endMinutes ?? 17 * 60;
  late bool _enabled = widget.initial?.enabled ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final value = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _start = picked.hour * 60 + picked.minute;
        } else {
          _end = picked.hour * 60 + picked.minute;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _day ?? PlanScope.maybeOf(context)?.todayDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty ||
        _start >= _end ||
        (_kind == 'recurring' && _weekdays.isEmpty) ||
        (_kind == 'one_off' && _day == null)) {
      setState(
        () => _error = 'Add a name, valid same-day times, and the applicable days or date.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = CommitmentDraft(
        title: title,
        category: _category,
        kind: _kind,
        weekdays: _kind == 'recurring'
            ? (_weekdays.toList()..sort())
            : const [],
        day: _kind == 'one_off' ? _day : null,
        startMinutes: _start,
        endMinutes: _end,
        enabled: _enabled,
      );
      final planDate = PlanScope.maybeOf(context)?.plan?.date;
      final affectsPlan =
          planDate != null &&
          ((widget.initial?.appliesOn(planDate) ?? false) ||
              draft.appliesOn(planDate));
      await CommitmentScope.maybeOf(context)!
          .save(draft, id: widget.initial?.id);
      if (!mounted) return;
      if (affectsPlan) PlanScope.maybeOf(context)?.markEdited();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save this commitment. Try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    if (widget.initial == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete commitment?'),
        content: const Text('Existing suggested plans keep their saved times.'),
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
    if (confirmed != true || !mounted) return;
    final planDate = PlanScope.maybeOf(context)?.plan?.date;
    final affectsPlan = planDate != null && widget.initial!.appliesOn(planDate);
    setState(() => _saving = true);
    try {
      await CommitmentScope.maybeOf(context)!.delete(widget.initial!.id);
      if (!mounted) return;
      if (affectsPlan) PlanScope.maybeOf(context)?.markEdited();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not delete this commitment. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final format =
        AuthScope.maybeOf(context)?.user?.profile.timeFormat ?? '24h';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null ? 'Add commitment' : 'Edit commitment',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'When does it happen?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in ['recurring', 'one_off'])
                ChoiceChip(
                  label: Text(
                    kind == 'recurring' ? 'Regular schedule' : 'One-off',
                  ),
                  selected: _kind == kind,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Category', style: TextStyle(fontWeight: FontWeight.w900)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final category in categories)
                ChoiceChip(
                  label: Text(
                    category[0].toUpperCase() + category.substring(1),
                  ),
                  selected: _category == category,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                          if (_title.text ==
                              _category[0].toUpperCase() +
                                  _category.substring(1)) {
                            _title.text =
                                category[0].toUpperCase() +
                                category.substring(1);
                          }
                          _category = category;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            maxLength: 80,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Name',
              helperText: 'Preset names can be changed if needed.',
            ),
          ),
          if (_kind == 'recurring') ...[
            const Text(
              'Weekdays',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (var index = 0; index < 7; index++)
                  FilterChip(
                    label: Text(days[index]),
                    selected: _weekdays.contains(index),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(index);
                            } else {
                              _weekdays.remove(index);
                            }
                          }),
                  ),
              ],
            ),
          ] else
            ListTile(
              title: const Text('Date'),
              subtitle: Text(_day == null ? 'Choose a date' : formatDay(_day!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _saving ? null : _pickDate,
            ),
          ListTile(
            title: const Text('Start time'),
            subtitle: Text(formatPlanMinutes(_start, format)),
            trailing: const Icon(Icons.schedule),
            onTap: _saving ? null : () => _pickTime(true),
          ),
          ListTile(
            title: const Text('End time'),
            subtitle: Text(formatPlanMinutes(_end, format)),
            trailing: const Icon(Icons.schedule),
            onTap: _saving ? null : () => _pickTime(false),
          ),
          SwitchListTile(
            title: const Text('Active'),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          if (_saving)
            const Center(child: CircularProgressIndicator())
          else
            SolidAction(label: 'Save commitment', onTap: _save),
          if (widget.initial != null && !_saving)
            TextButton(
              onPressed: _delete,
              child: const Text('Delete commitment'),
            ),
        ],
      ),
    );
  }
}
