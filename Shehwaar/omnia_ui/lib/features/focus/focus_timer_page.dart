import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/focus/focus_preset.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';

String formatCountdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil();
  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

class FocusTimerPage extends StatelessWidget {
  const FocusTimerPage({super.key});

  static const _custom = -1;

  static Future<void> _choose(
    BuildContext context,
    FocusTimerController timer,
    int choice,
  ) async {
    final next = choice == _custom
        ? await showDialog<FocusPreset>(
            context: context,
            builder: (_) => _CustomPresetDialog(
              initial: timer.preset.isCustom ? timer.preset : null,
            ),
          )
        : FocusPreset.builtIns[choice];
    if (next == null || !context.mounted) return;
    if (timer.inProgress) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change timer?'),
          content: const Text('The current session will be reset.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    timer.selectPreset(next);
  }

  @override
  Widget build(BuildContext context) {
    final timer = FocusTimerScope.of(context);
    final focus = timer.phase == FocusPhase.focus;
    final color = focus ? blue : mint;
    final selected = timer.preset.isCustom
        ? _custom
        : FocusPreset.builtIns.indexOf(timer.preset);
    final finished = timer.justFinished;
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: const Text(
          'Focus Timer',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (i, preset) in FocusPreset.builtIns.indexed)
                  ButtonSegment(value: i, label: Text(preset.label)),
                const ButtonSegment(value: _custom, label: Text('Custom')),
              ],
              selected: {selected},
              onSelectionChanged: (choice) =>
                  _choose(context, timer, choice.single),
            ),
            if (timer.preset.isCustom)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _choose(context, timer, _custom),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Edit custom'),
                ),
              ),
            const SizedBox(height: 18),
            HardCard(
              color: color,
              child: Column(
                children: [
                  Row(
                    children: [
                      LabelTag(text: focus ? 'FOCUS' : 'BREAK'),
                      const Spacer(),
                      Text(
                        '${timer.preset.name} · ${timer.preset.label}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    formatCountdown(timer.remaining),
                    style: const TextStyle(
                      fontSize: 72,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 24),
                  OmniaProgressBar(
                    value: timer.progress,
                    color: color,
                    height: 10,
                  ),
                ],
              ),
            ),
            if (finished != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finished == FocusPhase.focus
                          ? 'Focus complete. Time for a break.'
                          : 'Break over. Ready to focus?',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: timer.running
                        ? 'Pause'
                        : timer.paused
                        ? 'Resume'
                        : focus
                        ? 'Start focus'
                        : 'Start break',
                    onTap: timer.running
                        ? timer.pause
                        : timer.paused
                        ? timer.resume
                        : timer.start,
                  ),
                ),
                const SizedBox(width: 8),
                _smallAction(context, Icons.replay, 'Reset', timer.reset),
                const SizedBox(width: 8),
                _smallAction(context, Icons.skip_next, 'Skip', timer.skip),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Focus sessions completed: ${timer.completedFocusSessions}',
                style: TextStyle(color: context.mutedForeground, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onPressed,
  ) => Expanded(
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        side: BorderSide(color: context.outline, width: 1.5),
      ),
    ),
  );
}

class _CustomPresetDialog extends StatefulWidget {
  const _CustomPresetDialog({this.initial});
  final FocusPreset? initial;
  @override
  State<_CustomPresetDialog> createState() => _CustomPresetDialogState();
}

class _CustomPresetDialogState extends State<_CustomPresetDialog> {
  final _form = GlobalKey<FormState>();
  late final _focus = TextEditingController(
    text: '${(widget.initial ?? FocusPreset.standard).focus.inMinutes}',
  );
  late final _rest = TextEditingController(
    text: '${(widget.initial ?? FocusPreset.standard).rest.inMinutes}',
  );

  @override
  void dispose() {
    _focus.dispose();
    _rest.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      FocusPreset.custom(
        focusMinutes: int.parse(_focus.text.trim()),
        breakMinutes: int.parse(_rest.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom timer'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _focus,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Focus minutes'),
            validator: (value) => FocusPreset.validateMinutes(
              value,
              max: FocusPreset.maxFocusMinutes,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _rest,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Break minutes'),
            validator: (value) => FocusPreset.validateMinutes(
              value,
              max: FocusPreset.maxBreakMinutes,
            ),
            onFieldSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Apply')),
    ],
  );
}
