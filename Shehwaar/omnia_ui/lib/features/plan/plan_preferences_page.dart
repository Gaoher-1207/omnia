import 'package:flutter/material.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/commitment_form_page.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_time.dart';

class PlanPreferencesPage extends StatefulWidget {
  const PlanPreferencesPage({super.key});
  @override
  State<PlanPreferencesPage> createState() => _PlanPreferencesPageState();
}

class _PlanPreferencesPageState extends State<PlanPreferencesPage> {
  late final _profile = AuthScope.read(context).user!.profile;
  late int _start = _profile.planningStartMinutes,
      _end = _profile.planningEndMinutes;
  late String _format = _profile.timeFormat;
  bool _saving = false;
  String? _error;

  bool _loadedCommitments = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedCommitments) {
      _loadedCommitments = true;
      final commitments = CommitmentScope.maybeOf(context);
      if (commitments != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) commitments.loadAll();
        });
      }
    }
  }

  void _openCommitment({Commitment? initial, String kind = 'recurring'}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CommitmentFormPage(initial: initial, initialKind: kind),
      ),
    );
  }

  Future<void> _pick(bool start) async {
    final minutes = start ? _start : _end;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: _format == '24h'),
        child: child!,
      ),
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _start = value.hour * 60 + value.minute;
        } else {
          _end = value.hour * 60 + value.minute;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_start >= _end) {
      setState(
        () => _error = 'End must be after start on the same day. Overnight planning is not supported.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthScope.read(context).updateProfile({
        'planning_start_minutes': _start,
        'planning_end_minutes': _end,
        'time_format': _format,
      });
      if (mounted) {
        await CommitmentScope.maybeOf(
          context,
        )?.loadForDate(PlanScope.maybeOf(context)?.selectedDate, force: true);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save preferences. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan preferences')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Planning day · ${_profile.timezone}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const Text('Start and end must be on the same day.'),
        ListTile(
          title: const Text('Start time'),
          subtitle: Text(formatPlanMinutes(_start, _format)),
          trailing: const Icon(Icons.schedule),
          onTap: _saving ? null : () => _pick(true),
        ),
        ListTile(
          title: const Text('End time'),
          subtitle: Text(formatPlanMinutes(_end, _format)),
          trailing: const Icon(Icons.schedule),
          onTap: _saving ? null : () => _pick(false),
        ),
        const Text('Time format'),
        Wrap(
          spacing: 8,
          children: [
            for (final format in ['12h', '24h'])
              ChoiceChip(
                label: Text(format == '12h' ? '12-hour' : '24-hour'),
                selected: _format == format,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _format = format),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Saved hours apply to your next generated suggestion. Existing suggestions keep their original schedule.',
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
          SolidAction(label: 'Save', onTap: _save),
        if (CommitmentScope.maybeOf(context) case final commitments?) ...[
          const SizedBox(height: 26),
          const Text(
            'Regular schedule',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          for (final row in commitments.rows.where(
            (item) => item.kind == 'recurring',
          ))
            _CommitmentTile(
              row: row,
              format: _format,
              onTap: () => _openCommitment(initial: row),
            ),
          TextButton.icon(
            onPressed: () => _openCommitment(),
            icon: const Icon(Icons.add),
            label: const Text('Add regular commitment'),
          ),
          const SizedBox(height: 12),
          const Text(
            'One-off commitments',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          for (final row in commitments.rows.where(
            (item) => item.kind == 'one_off',
          ))
            _CommitmentTile(
              row: row,
              format: _format,
              onTap: () => _openCommitment(initial: row),
            ),
          TextButton.icon(
            onPressed: () => _openCommitment(kind: 'one_off'),
            icon: const Icon(Icons.add),
            label: const Text('Add one-off commitment'),
          ),
          if (commitments.busy)
            const Center(child: CircularProgressIndicator()),
          if (commitments.error != null)
            TextButton(
              onPressed: () => commitments.loadAll(force: true),
              child: const Text('Could not load commitments. Retry'),
            ),
        ],
      ],
    ),
  );
}

class _CommitmentTile extends StatelessWidget {
  const _CommitmentTile({
    required this.row,
    required this.format,
    required this.onTap,
  });
  final Commitment row;
  final String format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(row.title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      [
        if (row.kind == 'recurring')
          [
            for (final day in row.weekdays)
              ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day],
          ].join(' ')
        else if (row.day != null)
          row.day!.toIso8601String().substring(0, 10),
        '${formatPlanMinutes(row.startMinutes, format)}–${formatPlanMinutes(row.endMinutes, format)}',
        if (!row.enabled) 'Paused',
      ].join(' · '),
    ),
    trailing: const Icon(Icons.edit_outlined),
    onTap: onTap,
  );
}
