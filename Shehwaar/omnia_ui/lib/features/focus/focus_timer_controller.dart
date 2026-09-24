import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/focus/focus_preset.dart';

enum FocusPhase { focus, rest }

/// One reusable Pomodoro timer. Future Focus Mode should drive this same
/// controller rather than adding a second countdown.
///
/// Remaining time is always derived from a deadline, so delayed ticks, route
/// changes or a briefly inactive app do not drift the countdown. A finished
/// phase moves to the next one and waits for the user to start it.
class FocusTimerController extends ChangeNotifier {
  FocusTimerController({
    FocusPreset preset = FocusPreset.standard,
    DateTime Function()? now,
  }) : _preset = preset,
       _now = now ?? DateTime.now,
       _remaining = preset.focus;

  final DateTime Function() _now;
  FocusPreset _preset;
  FocusPhase _phase = FocusPhase.focus;
  Duration _remaining;
  DateTime? _deadline;
  Timer? _ticker;
  int _completedFocusSessions = 0;
  FocusPhase? _justFinished;
  int _shownSeconds = -1;

  FocusPreset get preset => _preset;
  FocusPhase get phase => _phase;
  int get completedFocusSessions => _completedFocusSessions;

  /// The phase that just ran out naturally; cleared by any user action.
  FocusPhase? get justFinished => _justFinished;

  Duration get phaseDuration =>
      _phase == FocusPhase.focus ? _preset.focus : _preset.rest;
  bool get running => _deadline != null;
  bool get paused => !running && _remaining < phaseDuration;

  /// True once the current phase has been started and not reset.
  bool get inProgress => running || paused;

  Duration get remaining {
    final deadline = _deadline;
    if (deadline == null) return _remaining;
    final left = deadline.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  double get progress =>
      1 - remaining.inMilliseconds / phaseDuration.inMilliseconds;

  void start() {
    if (running) return;
    _justFinished = null;
    _deadline = _now().add(_remaining);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => tick());
    notifyListeners();
  }

  void resume() => start();

  void pause() {
    if (!running) return;
    _remaining = remaining;
    _stop();
    notifyListeners();
  }

  /// Returns to the start of a Focus phase. Completed sessions are kept.
  void reset() {
    _stop();
    _justFinished = null;
    _setPhase(FocusPhase.focus);
    notifyListeners();
  }

  /// Ends the current phase early without counting it as completed.
  void skip() {
    _stop();
    _justFinished = null;
    _setPhase(_phase == FocusPhase.focus ? FocusPhase.rest : FocusPhase.focus);
    notifyListeners();
  }

  /// Applies [preset] and resets. Callers confirm first when [inProgress].
  void selectPreset(FocusPreset preset) {
    _preset = preset;
    reset();
  }

  /// Re-reads the clock. Called by the ticker; public so tests can drive it.
  @visibleForTesting
  void tick() {
    if (!running) return;
    if (remaining > Duration.zero) {
      final seconds = (remaining.inMilliseconds / 1000).ceil();
      if (seconds != _shownSeconds) {
        _shownSeconds = seconds;
        notifyListeners();
      }
      return;
    }
    _stop();
    _justFinished = _phase;
    if (_phase == FocusPhase.focus) {
      _completedFocusSessions++;
      _setPhase(FocusPhase.rest);
    } else {
      _setPhase(FocusPhase.focus);
    }
    notifyListeners();
  }

  void _setPhase(FocusPhase phase) {
    _phase = phase;
    _remaining = phaseDuration;
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    _shownSeconds = -1;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class FocusTimerScope extends InheritedNotifier<FocusTimerController> {
  const FocusTimerScope({
    super.key,
    required FocusTimerController controller,
    required super.child,
  }) : super(notifier: controller);

  static FocusTimerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusTimerScope>()!.notifier!;
}
