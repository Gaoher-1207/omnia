import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';

String phaseFinishedMessage(FocusPhase finished) => finished == FocusPhase.focus
    ? 'Focus complete. Time for a break.'
    : 'Break over. Ready to focus?';

/// App-wide, so a phase that runs out on any screen is still felt and heard.
/// Fires once per natural finish: [FocusTimerController.justFinished] only
/// becomes non-null there, and every user action clears it again.
class FocusPhaseFeedback extends StatefulWidget {
  const FocusPhaseFeedback({
    super.key,
    required this.controller,
    required this.child,
  });
  final FocusTimerController controller;
  final Widget child;

  @override
  State<FocusPhaseFeedback> createState() => _FocusPhaseFeedbackState();
}

class _FocusPhaseFeedbackState extends State<FocusPhaseFeedback> {
  FocusPhase? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.controller.justFinished;
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final finished = widget.controller.justFinished;
    if (finished != null && _last == null) {
      HapticFeedback.heavyImpact();
      SemanticsService.sendAnnouncement(
        View.of(context),
        phaseFinishedMessage(finished),
        Directionality.of(context),
      );
    }
    _last = finished;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
