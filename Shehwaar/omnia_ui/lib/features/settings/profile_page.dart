import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/auth/timezones.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// Profile and daily targets (`PATCH /profile`), API mode only. Daily
/// targets are what Home and Track measure each day; long-term Goals are a
/// separate feature and are not edited here.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  late final Profile _initial = AuthScope.read(context).user!.profile;
  late final _name = TextEditingController(text: _initial.displayName);
  late final _username = TextEditingController(text: _initial.username ?? '');
  late final _study = _number(_initial.studyGoalMinutes);
  late final _steps = _number(_initial.stepGoal);
  late final _tasks = _number(_initial.taskGoal);
  late final _sleep = _number(_initial.sleepGoalMinutes);
  late final _calories = _number(_initial.calorieGoal);
  late String _timezone = _initial.timezone;
  late WorkoutTime _workout = _initial.workoutTime;
  bool _saving = false;
  ApiException? _error;

  static TextEditingController _number(int value) =>
      TextEditingController(text: '$value');

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _study,
      _steps,
      _tasks,
      _sleep,
      _calories,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Profile _edited() {
    final username = _username.text.trim().toLowerCase();
    return Profile(
      displayName: _name.text.trim(),
      timezone: _timezone,
      username: username.isEmpty ? null : username,
      studyGoalMinutes: int.parse(_study.text),
      stepGoal: int.parse(_steps.text),
      taskGoal: int.parse(_tasks.text),
      sleepGoalMinutes: int.parse(_sleep.text),
      calorieGoal: int.parse(_calories.text),
      workoutTime: _workout,
    );
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      // The form is longer than a screen: the problem may be out of view.
      showDone(context, _checkFields);
      return;
    }
    final changes = _edited().changesSince(_initial);
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final dashboard = DashboardScope.read(context);
    setState(() => _saving = true);
    try {
      await AuthScope.read(context).updateProfile(changes);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
      _shownOnAField(error)
          ? showDone(context, _checkFields)
          : showError(context, error);
      return;
    }
    // Saved. Home and Track show the new targets, name and day once the
    // dashboard reloads; if that fails the save still stands.
    await dashboard.load();
    if (!mounted) return;
    showDone(
      context,
      dashboard.loadError == null
          ? 'Profile saved.'
          : "Profile saved, but Home couldn't refresh. Pull down on Home to "
                'try again.',
    );
    Navigator.pop(context);
  }

  static const _checkFields = 'Check the highlighted fields.';

  static const _fields = [
    'display_name',
    'username',
    'timezone',
    'daily_study_goal_minutes',
    'daily_step_goal',
    'daily_task_goal',
    'daily_sleep_goal_minutes',
    'daily_calorie_goal',
    'preferred_workout_time',
  ];

  bool _shownOnAField(ApiException error) =>
      error.code == 'conflict' ||
      _fields.any((field) => error.fieldMessage(field) != null);

  String? _serverError(String field) {
    final error = _error;
    if (error == null) return null;
    // The only unique profile field; the backend reports it without a field.
    if (field == 'username' && error.code == 'conflict') return error.message;
    return error.fieldMessage(field);
  }

  Widget _target({
    required TextEditingController controller,
    required String label,
    required String field,
    required int max,
    bool minutes = false,
  }) {
    final value = int.tryParse(controller.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          // "= 4h", live, so minute targets read naturally.
          helperText: minutes && value != null && value <= max
              ? '= ${formatDuration(Duration(minutes: value))}'
              : '0 to $max · 0 turns it off',
          helperMaxLines: 2,
          errorText: _serverError(field),
          errorMaxLines: 3,
        ),
        onChanged: minutes ? (_) => setState(() {}) : null,
        validator: (text) {
          final n = int.tryParse(text?.trim() ?? '');
          return n == null || n > max ? 'Enter a number from 0 to $max' : null;
        },
      ),
    );
  }

  Widget _heading(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final zones = commonTimezones.contains(_timezone)
        ? commonTimezones
        : [_timezone, ...commonTimezones];
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & targets')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _heading('Profile'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _serverError('display_name'),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _username,
              maxLength: 30,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Username (optional)',
                prefixText: '@',
                helperText:
                    '3–30 letters, digits or _. Friends find you by it.',
                helperMaxLines: 3,
                errorText: _serverError('username'),
                errorMaxLines: 3,
              ),
              validator: (value) {
                final text = (value ?? '').trim().toLowerCase();
                return text.isEmpty ||
                        RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(text)
                    ? null
                    : 'Use 3–30 letters, digits or _';
              },
            ),
            const SizedBox(height: 8),
            SelectField<String>(
              label: 'Time zone',
              initialValue: _timezone,
              helperText: 'Decides when your day starts.',
              errorText: _serverError('timezone'),
              searchable: true,
              options: [
                for (final zone in zones)
                  SelectOption(zone, zone.replaceAll('_', ' ')),
              ],
              onChanged: (value) => setState(() => _timezone = value),
            ),
            const SizedBox(height: 24),
            _heading('Daily targets'),
            const SizedBox(height: 4),
            const Text(
              'What Today and Areas measure each day. Your long-term Goals '
              'are separate.',
            ),
            const SizedBox(height: 14),
            _target(
              controller: _study,
              label: 'Study (minutes a day)',
              field: 'daily_study_goal_minutes',
              max: 960,
              minutes: true,
            ),
            _target(
              controller: _steps,
              label: 'Steps a day',
              field: 'daily_step_goal',
              max: 100000,
            ),
            _target(
              controller: _tasks,
              label: 'Tasks completed a day',
              field: 'daily_task_goal',
              max: 50,
            ),
            _target(
              controller: _sleep,
              label: 'Sleep (minutes a night)',
              field: 'daily_sleep_goal_minutes',
              max: 960,
              minutes: true,
            ),
            _target(
              controller: _calories,
              label: 'Calories a day',
              field: 'daily_calorie_goal',
              max: 10000,
            ),
            const SizedBox(height: 4),
            SelectField<WorkoutTime>(
              label: 'Preferred workout time',
              initialValue: _workout,
              helperText: 'Used when planning your day.',
              errorText: _serverError('preferred_workout_time'),
              options: [
                for (final time in WorkoutTime.values)
                  SelectOption(
                    time,
                    time.name[0].toUpperCase() + time.name.substring(1),
                  ),
              ],
              onChanged: (value) => setState(() => _workout = value),
            ),
            const SizedBox(height: 24),
            SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
          ],
        ),
      ),
    );
  }
}
