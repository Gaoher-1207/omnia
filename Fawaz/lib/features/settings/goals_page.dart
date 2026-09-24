import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/auth/timezones.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';

/// Profile and daily goals (PATCH /api/profile).
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _form = GlobalKey<FormState>();
  late final Profile _profile = AuthScope.read(context).user!.profile;
  late final _name = TextEditingController(text: _profile.displayName);
  late final _username = TextEditingController(text: _profile.username ?? '');
  late final _study = TextEditingController(text: '${_profile.studyGoalMinutes}');
  late final _tasks = TextEditingController(text: '${_profile.taskGoal}');
  late final _steps = TextEditingController(text: '${_profile.stepGoal}');
  late final _sleep = TextEditingController(text: '${_profile.sleepGoalMinutes}');
  late final _calories = TextEditingController(text: '${_profile.calorieGoal}');
  late WorkoutTime _workout = _profile.workoutTime;
  late String _timezone = _profile.timezone;
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _study, _tasks, _steps, _sleep, _calories]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final username = _username.text.trim().toLowerCase();
    try {
      await AuthScope.read(context).updateProfile({
        'display_name': _name.text.trim(),
        'username': username.isEmpty ? null : username,
        'daily_study_goal_minutes': int.parse(_study.text),
        'daily_task_goal': int.parse(_tasks.text),
        'daily_step_goal': int.parse(_steps.text),
        'daily_sleep_goal_minutes': int.parse(_sleep.text),
        'daily_calorie_goal': int.parse(_calories.text),
        'preferred_workout_time': _workout.name,
        'timezone': _timezone,
      });
      if (!mounted) return;
      await SessionScope.refreshDashboard(context);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
      if (mounted && error.details.isEmpty) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _number(TextEditingController c, String label, String field, int max, {String? helper}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, helperText: helper, errorText: _error?.fieldMessage(field)),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        return n == null || n < 0 || n > max ? 'Enter 0 to $max' : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final zones = commonTimezones.contains(_timezone) ? commonTimezones : [_timezone, ...commonTimezones];
    return Scaffold(
      appBar: AppBar(title: const Text('Goals & profile')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(labelText: 'Name', errorText: _error?.fieldMessage('display_name')),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null,
            ),
            TextFormField(
              controller: _username,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: 'Username (for friends)',
                prefixText: '@',
                helperText: '3–30 letters, digits or _',
                errorText: _error?.fieldMessage('username') ??
                    (_error?.code == 'conflict' ? _error!.message : null),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(t) ? null : '3–30 letters, digits or _';
              },
            ),
            const SizedBox(height: 8),
            _number(_study, 'Study goal (minutes a day)', 'daily_study_goal_minutes', 960),
            _number(_tasks, 'Tasks a day', 'daily_task_goal', 50),
            _number(_steps, 'Steps a day', 'daily_step_goal', 100000),
            _number(_sleep, 'Sleep goal (minutes a night)', 'daily_sleep_goal_minutes', 960, helper: '480 = 8 hours'),
            _number(_calories, 'Calories a day', 'daily_calorie_goal', 10000),
            const Text('Preferred workout time', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<WorkoutTime>(
              segments: const [
                ButtonSegment(value: WorkoutTime.morning, label: Text('Morning')),
                ButtonSegment(value: WorkoutTime.afternoon, label: Text('Afternoon')),
                ButtonSegment(value: WorkoutTime.evening, label: Text('Evening')),
              ],
              selected: {_workout},
              onSelectionChanged: (s) => setState(() => _workout = s.single),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _timezone,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Timezone', errorText: _error?.fieldMessage('timezone')),
              items: [for (final z in zones) DropdownMenuItem(value: z, child: Text(z.replaceAll('_', ' ')))],
              onChanged: (v) => setState(() => _timezone = v ?? _timezone),
            ),
            const SizedBox(height: 24),
            SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
          ],
        ),
      ),
    );
  }
}
