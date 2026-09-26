import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';
import 'package:omnia_ui/features/track/track_controller.dart';

/// Common workouts. The server stores any string; anything else is "Other".
const workoutTypes = [
  'Strength training',
  'Running',
  'Walking',
  'Cycling',
  'Swimming',
  'Sports',
  'HIIT',
  'Yoga / Mobility',
];
const _other = 'Other';

/// Log or edit today's steps and workout. "Today" is the dashboard's day,
/// worked out by the server in the user's time zone.
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key, required this.day});
  final DateTime day;

  /// Opens today's activity, or explains why it can't yet: without a loaded
  /// dashboard there is no server day to log against.
  static void open(BuildContext context) {
    final day = DashboardScope.read(context).dashboard?.date;
    if (day == null) {
      showDone(context, notLoadedMessage);
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ActivityLogPage(day: day)),
    );
  }

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final _form = GlobalKey<FormState>();
  final _steps = TextEditingController();
  final _minutes = TextEditingController();
  final _type = TextEditingController(); // Other's own text
  String? _choice; // a [workoutTypes] entry, [_other], or none
  bool _workout = false, _loading = true, _saving = false;
  Object? _loadError;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _steps.dispose();
    _minutes.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final day = await TrackScope.read(context).activity(widget.day);
      if (!mounted) return;
      setState(() {
        _steps.text = '${day.steps}';
        _workout = day.workoutDone;
        _minutes.text = day.workoutDone ? '${day.workoutMinutes}' : '';
        final type = day.workoutType ?? '';
        // A value from elsewhere (older app, API) stays as Other's text,
        // so saving never loses it.
        _choice = type.isEmpty
            ? null
            : workoutTypes.contains(type)
            ? type
            : _other;
        _type.text = _choice == _other ? type : '';
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final type = _choice == _other ? _type.text.trim() : _choice;
    final activity = ActivityDay(
      day: widget.day,
      steps: int.parse(_steps.text),
      workoutDone: _workout,
      workoutMinutes: _workout ? int.tryParse(_minutes.text) ?? 0 : 0,
      workoutType: _workout ? type : null,
    );
    setState(() => _saving = true);
    final TrackSave result;
    try {
      result = await TrackScope.read(context).saveActivity(activity);
    } on ApiException catch (error) {
      if (!mounted) return; // e.g. the session ended
      setState(() {
        _saving = false;
        _error = error;
      });
      showError(context, error);
      return;
    }
    if (!mounted) return;
    if (result == TrackSave.ignored) {
      setState(() => _saving = false);
      return;
    }
    showDone(context, savedMessage('Activity saved', result));
    Navigator.pop(context);
  }

  static String? _range(String? text, int max, {required bool required}) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return required ? 'Enter a number' : null;
    final n = int.tryParse(value);
    return n == null || n > max
        ? 'Enter a number from 0 to ${formatCount(max)}'
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activity')),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading activity',
            ),
          )
        : _loadError != null
        ? ErrorView(
            title: "Couldn't load your activity",
            error: _loadError!,
            onRetry: _load,
          )
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  'Today  ·  ${formatLongDate(widget.day)}',
                  style: TextStyle(color: context.mutedForeground),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _steps,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Steps',
                    helperText: 'Everything you walked today.',
                    errorText: _error?.fieldMessage('steps'),
                    errorMaxLines: 3,
                  ),
                  validator: (text) => _range(text, 200000, required: true),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Workout done'),
                  value: _workout,
                  onChanged: (value) => setState(() => _workout = value),
                ),
                if (_workout) ...[
                  TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Workout minutes',
                      errorText: _error?.fieldMessage('workout_minutes'),
                      errorMaxLines: 3,
                    ),
                    validator: (text) => _range(text, 600, required: false),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _choice,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Workout type (optional)',
                      errorText: _choice == _other
                          ? null
                          : _error?.fieldMessage('workout_type'),
                      errorMaxLines: 3,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Not specified'),
                      ),
                      for (final type in [...workoutTypes, _other])
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (value) => setState(() => _choice = value),
                  ),
                  if (_choice == _other) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _type,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Other workout',
                        errorText: _error?.fieldMessage('workout_type'),
                        errorMaxLines: 3,
                      ),
                      validator: (text) => (text?.trim() ?? '').isEmpty
                          ? 'Describe the workout'
                          : null,
                    ),
                  ],
                ] else if (_minutes.text.isNotEmpty || _choice != null)
                  Text(
                    'Saving without a workout clears its minutes and type.',
                    style: TextStyle(color: context.mutedForeground),
                  ),
                const SizedBox(height: 24),
                SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
              ],
            ),
          ),
  );
}
