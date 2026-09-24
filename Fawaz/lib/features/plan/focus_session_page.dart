import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';

/// A simple focus timer. Finishing logs the time as a study session.
/// Pops with `true` when a session was saved.
class FocusSessionPage extends StatefulWidget {
  const FocusSessionPage({super.key, required this.title, this.subjectId});
  final String title;
  final String? subjectId;

  @override
  State<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends State<FocusSessionPage> {
  final _watch = Stopwatch();
  Timer? _ticker;
  bool _saving = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_watch.isRunning) {
        _watch.stop();
        _ticker?.cancel();
      } else {
        _watch.start();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  Future<void> _finish() async {
    final minutes = (_watch.elapsed.inSeconds / 60).round();
    if (minutes < 1) {
      showDone(context, 'Focus for at least a minute to log it.');
      return;
    }
    _watch.stop();
    _ticker?.cancel();
    setState(() => _saving = true);
    try {
      await AppDependenciesScope.of(context).study.logSession(
        minutes: minutes.clamp(1, 720),
        subjectId: widget.subjectId,
      );
      if (!mounted) return;
      showDone(context, 'Logged $minutes minutes of study.');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, error);
    }
  }

  String get _clock {
    final e = _watch.elapsed;
    final h = e.inHours, m = e.inMinutes % 60, s = e.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(title: const Text('Focus session', style: TextStyle(fontWeight: FontWeight.w900))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          HardCard(
            color: blue,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  _clock,
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SolidAction(label: _watch.isRunning ? 'Pause' : (_watch.elapsed == Duration.zero ? 'Start' : 'Resume'), onTap: _toggle),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _saving ? null : _finish,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.foreground,
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: BorderSide(color: context.outline, width: 1.5),
            ),
            child: Text(_saving ? 'Saving…' : 'Finish and log time'),
          ),
          const SizedBox(height: 12),
          Text(
            'Time is saved as a study session when you finish. Leaving this screen discards it.',
            style: TextStyle(color: context.mutedForeground, fontSize: 12),
          )
        ],
      ),
    ),
  );
}
