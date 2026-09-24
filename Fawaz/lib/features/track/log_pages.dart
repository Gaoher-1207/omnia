import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';

DateTime _today(BuildContext context) =>
    ControllerScope.read<DashboardState>(context).data?.date ?? DateUtils.dateOnly(DateTime.now());

/// Day picker row shared by the log pages.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.day, required this.today, required this.onChanged});
  final DateTime day, today;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: today.subtract(const Duration(days: 90)),
        lastDate: today,
      );
      if (picked != null) onChanged(DateUtils.dateOnly(picked));
    },
    icon: const Icon(Icons.event_outlined),
    label: Text(DateUtils.isSameDay(day, today) ? 'Today' : longDate(day)),
    style: OutlinedButton.styleFrom(
      foregroundColor: context.foreground,
      side: BorderSide(color: context.outline, width: 1.5),
    ),
  );
}

// ----------------------------------------------------------------- activity

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});
  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final _form = GlobalKey<FormState>();
  final _steps = TextEditingController();
  final _minutes = TextEditingController();
  final _type = TextEditingController();
  late DateTime _day = _today(context);
  late final DateTime _todayDate = _today(context);
  bool _workout = false, _loading = true, _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _steps.dispose();
    _minutes.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await AppDependenciesScope.of(context).track.activity(_day);
      if (!mounted) return;
      setState(() {
        _steps.text = '${day.steps}';
        _workout = day.workoutDone;
        _minutes.text = day.workoutMinutes == 0 ? '' : '${day.workoutMinutes}';
        _type.text = day.workoutType ?? '';
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppDependenciesScope.of(context).track.saveActivity(
        _day,
        steps: int.parse(_steps.text.trim()),
        workoutDone: _workout,
        workoutMinutes: int.tryParse(_minutes.text.trim()) ?? 0,
        workoutType: _type.text,
      );
      if (!mounted) return;
      await SessionScope.refreshDashboard(context);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(title: const Text('Activity', style: TextStyle(fontWeight: FontWeight.w900))),
    body: SafeArea(
      child: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _loading
          ? const LoadingView()
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _DayPicker(
                    day: _day,
                    today: _todayDate,
                    onChanged: (day) {
                      _day = day;
                      _load();
                    },
                  ),
                  const SizedBox(height: 16),
                  HardCard(
                    color: mint,
                    child: TextFormField(
                      controller: _steps,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Steps'),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        return n == null || n < 0 || n > 200000 ? 'Enter steps from 0 to 200,000' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _workout,
                    onChanged: (v) => setState(() => _workout = v),
                    title: const Text('Workout done', style: TextStyle(fontWeight: FontWeight.w800)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_workout) ...[
                    TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Workout minutes'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        return n == null || n > 600 ? 'Enter minutes from 0 to 600' : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _type,
                      maxLength: 40,
                      decoration: const InputDecoration(labelText: 'Type (optional)', hintText: 'Gym, run, yoga…'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
                ],
              ),
            ),
    ),
  );
}

// -------------------------------------------------------------------- sleep

class SleepLogPage extends StatefulWidget {
  const SleepLogPage({super.key});
  @override
  State<SleepLogPage> createState() => _SleepLogPageState();
}

class _SleepLogPageState extends State<SleepLogPage> {
  late DateTime _day = _today(context);
  late final DateTime _todayDate = _today(context);
  int _minutes = 7 * 60;
  int? _quality;
  bool _loading = true, _saving = false, _logged = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entry = await AppDependenciesScope.of(context).track.sleep(_day);
      if (!mounted) return;
      setState(() {
        _logged = entry.logged;
        if (entry.logged) _minutes = entry.minutes;
        _quality = entry.quality;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppDependenciesScope.of(context).track.saveSleep(_day, minutes: _minutes, quality: _quality);
      if (!mounted) return;
      await SessionScope.refreshDashboard(context);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(title: const Text('Sleep', style: TextStyle(fontWeight: FontWeight.w900))),
    body: SafeArea(
      child: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _DayPicker(
                  day: _day,
                  today: _todayDate,
                  onChanged: (day) {
                    _day = day;
                    _load();
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Log the night that ended on this day.${_logged ? '' : ' Not logged yet.'}',
                  style: TextStyle(color: context.mutedForeground),
                ),
                const SizedBox(height: 16),
                HardCard(
                  color: lilac,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hoursLabel(_minutes), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      Slider(
                        value: _minutes.toDouble(),
                        min: 0,
                        max: 14 * 60,
                        divisions: 14 * 4,
                        label: hoursLabel(_minutes),
                        onChanged: (v) => setState(() => _minutes = v.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('How did you sleep?', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Awful')),
                    ButtonSegment(value: 2, label: Text('Poor')),
                    ButtonSegment(value: 3, label: Text('OK')),
                    ButtonSegment(value: 4, label: Text('Good')),
                    ButtonSegment(value: 5, label: Text('Great')),
                  ],
                  selected: {if (_quality != null) _quality!},
                  onSelectionChanged: (s) => setState(() => _quality = s.isEmpty ? null : s.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 8),
                Text(
                  'Short or poor sleep makes tomorrow’s plan lighter.',
                  style: TextStyle(color: context.mutedForeground, fontSize: 12),
                ),
                const SizedBox(height: 20),
                SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
              ],
            ),
    ),
  );
}
