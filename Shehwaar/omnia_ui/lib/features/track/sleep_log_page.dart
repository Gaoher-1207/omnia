import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/area_header.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';
import 'package:omnia_ui/features/track/track_controller.dart';

/// Log, edit or remove the sleep for the night ending on the dashboard's
/// day (the server's today in the user's time zone).
class SleepLogPage extends StatefulWidget {
  const SleepLogPage({super.key, required this.day});
  final DateTime day;

  /// Opens last night's sleep, or explains why it can't yet.
  static void open(BuildContext context) {
    final day = DashboardScope.read(context).dashboard?.date;
    if (day == null) {
      showDone(context, notLoadedMessage);
      return;
    }
    // A short form: it takes the whole screen, over the tab bar.
    Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(MaterialPageRoute(builder: (_) => SleepLogPage(day: day)));
  }

  @override
  State<SleepLogPage> createState() => _SleepLogPageState();
}

const _qualities = {1: 'Awful', 2: 'Poor', 3: 'OK', 4: 'Good', 5: 'Great'};

class _SleepLogPageState extends State<SleepLogPage> {
  final _form = GlobalKey<FormState>();
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  int? _quality;

  /// The stored entry, whose bedtime and wake time are sent back unchanged.
  SleepEntry? _entry;
  bool _loading = true, _saving = false;
  Object? _loadError;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
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
      final entry = await TrackScope.read(context).sleep(widget.day);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        if (entry != null) {
          _hours.text = '${entry.durationMinutes ~/ 60}';
          _minutes.text = '${entry.durationMinutes % 60}';
          _quality = entry.quality;
        }
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

  int? get _total {
    final hours = _hours.text.trim(), minutes = _minutes.text.trim();
    if (hours.isEmpty && minutes.isEmpty) return null;
    return (int.tryParse(hours) ?? 0) * 60 + (int.tryParse(minutes) ?? 0);
  }

  Future<void> _run(
    Future<TrackSave> Function(TrackController track) change,
    String done,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final TrackSave result;
    try {
      result = await change(TrackScope.read(context));
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
    showDone(context, savedMessage(done, result));
    Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final entry = _entry;
    await _run(
      (track) => track.saveSleep(
        SleepEntry(
          day: widget.day,
          durationMinutes: _total!,
          quality: _quality,
          bedtime: entry?.bedtime,
          wakeTime: entry?.wakeTime,
        ),
      ),
      'Sleep saved',
    );
  }

  Future<void> _remove() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this sleep entry?'),
        content: const Text('Home will show your sleep as not logged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((track) => track.deleteSleep(widget.day), 'Sleep entry removed');
  }

  String? _validateHours(String? _) {
    final total = _total;
    if (total == null) return 'Enter how long you slept';
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    if (hours > 24 || total > 24 * 60) return 'At most 24 hours';
    return null;
  }

  String? _validateMinutes(String? text) {
    final minutes = int.tryParse(text?.trim() ?? '') ?? 0;
    return minutes > 59 ? 'Enter 0 to 59' : null;
  }

  Widget _number(
    TextEditingController controller,
    String label,
    FormFieldValidator<String> validator,
  ) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, errorMaxLines: 3),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final times = [
      if (entry?.bedtime case final bedtime?)
        'bedtime ${bedtime.substring(0, 5)}',
      if (entry?.wakeTime case final wake?) 'wake time ${wake.substring(0, 5)}',
    ];
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Loading sleep'),
            )
          : _loadError != null
          ? ErrorView(
              title: "Couldn't load your sleep",
              error: _loadError!,
              onRetry: _load,
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  AreaHeader(
                    icon: Icons.dark_mode_outlined,
                    color: lilac,
                    eyebrow: 'Last night',
                    title: 'Sleep',
                    subtitle:
                        'The night ending ${formatLongDate(widget.day)}'
                        '${entry == null ? '  ·  not logged yet' : ''}',
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('How long you slept'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _number(_hours, 'Hours', _validateHours)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _number(_minutes, 'Minutes', _validateMinutes),
                      ),
                    ],
                  ),
                  if (_error?.fieldMessage('duration_minutes') case final m?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(m, style: TextStyle(color: danger)),
                    ),
                  const SizedBox(height: 22),
                  SelectField<int?>(
                    label: 'How did you sleep?',
                    initialValue: _quality,
                    errorText: _error?.fieldMessage('quality'),
                    options: [
                      const SelectOption(null, 'Not rated'),
                      for (final MapEntry(:key, :value) in _qualities.entries)
                        SelectOption(key, '$key · $value'),
                    ],
                    onChanged: (value) => setState(() => _quality = value),
                  ),
                  if (times.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Your logged ${times.join(' and ')} stay as they are.',
                      style: TextStyle(color: context.mutedForeground),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SolidAction(
                    label: _saving ? 'Saving…' : 'Save',
                    onTap: _save,
                  ),
                  if (entry != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _remove,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(
                        'Remove entry',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: danger,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: BorderSide(color: danger, width: 1.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
