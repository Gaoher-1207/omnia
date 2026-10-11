import 'package:omnia_ui/features/study/domain/study_log.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

enum InsightRange { week, month }

/// Fewer logged days than this give counts but no rates: two days of data
/// can't honestly be called a pattern.
const minDaysForRates = 3;

/// The calendar span shown for [range]: the Monday-to-Sunday week, or the
/// whole calendar month, that contains [today].
({DateTime from, DateTime to}) insightSpan(InsightRange range, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  return switch (range) {
    InsightRange.week => (
      from: day.subtract(Duration(days: day.weekday - DateTime.monday)),
      to: day.add(Duration(days: DateTime.sunday - day.weekday)),
    ),
    InsightRange.month => (
      from: DateTime(day.year, day.month),
      to: DateTime(day.year, day.month + 1, 0),
    ),
  };
}

enum DayState {
  /// After today: not part of any count.
  upcoming,

  /// Nothing was logged. Never counted as zero.
  notLogged,

  /// Logged without a workout / below the step goal.
  logged,

  /// Logged with a workout / at or above the step goal.
  hit,
}

class InsightDay {
  const InsightDay(this.day, this.activity, {required this.upcoming});
  final DateTime day;
  final ActivityDay? activity;
  final bool upcoming;
}

/// Workout and step figures computed only from logged days.
class ActivityInsights {
  ActivityInsights._(this.days, this.stepGoal);

  factory ActivityInsights.from(
    ActivityHistory history, {
    required DateTime from,
    required DateTime to,
    required DateTime today,
  }) {
    final last = DateTime(today.year, today.month, today.day);
    final days = <InsightDay>[];
    for (
      var day = DateTime(from.year, from.month, from.day);
      !day.isAfter(to);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final upcoming = day.isAfter(last);
      days.add(
        InsightDay(day, upcoming ? null : history.on(day), upcoming: upcoming),
      );
    }
    return ActivityInsights._(days, history.stepGoal);
  }

  final List<InsightDay> days;
  final int stepGoal;

  Iterable<ActivityDay> get _logged =>
      days.map((day) => day.activity).whereType<ActivityDay>();

  /// Days from the start of the span through today.
  int get elapsedDays => days.where((day) => !day.upcoming).length;
  int get loggedDays => _logged.length;
  int get notLoggedDays => elapsedDays - loggedDays;
  bool get hasData => loggedDays > 0;
  bool get enoughForRates => loggedDays >= minDaysForRates;

  int get workoutDays => _logged.where((day) => day.workoutDone).length;
  int get workoutMinutes =>
      _logged.fold(0, (total, day) => total + day.workoutMinutes);

  /// Share of logged days with a workout; null without enough logged days.
  double? get workoutRate => enoughForRates ? workoutDays / loggedDays : null;

  /// Mean over logged days only; null when nothing was logged.
  int? get averageSteps => hasData
      ? (_logged.fold(0, (total, day) => total + day.steps) / loggedDays)
            .round()
      : null;

  int get daysAtStepGoal =>
      stepGoal <= 0 ? 0 : _logged.where((day) => day.steps >= stepGoal).length;

  DayState workoutState(InsightDay day) => day.upcoming
      ? DayState.upcoming
      : day.activity == null
      ? DayState.notLogged
      : day.activity!.workoutDone
      ? DayState.hit
      : DayState.logged;

  DayState stepState(InsightDay day) => day.upcoming
      ? DayState.upcoming
      : day.activity == null
      ? DayState.notLogged
      : stepGoal > 0 && day.activity!.steps >= stepGoal
      ? DayState.hit
      : DayState.logged;
}

/// Study minutes per day for the same span: Focus sessions, plan blocks
/// checked off, and hand-logged study. A day without any is "no study
/// recorded"; study has no separate "not logged" state.
class StudyInsights {
  StudyInsights._(
    this.days,
    this._minutes,
    this.planMinutes,
    this.focusMinutes,
  );

  factory StudyInsights.from(
    List<StudyLog> log, {
    required DateTime from,
    required DateTime to,
    required DateTime today,
  }) {
    final byDay = <String, int>{};
    var plan = 0, focus = 0;
    for (final entry in log) {
      if (entry.day.isBefore(from) || entry.day.isAfter(to)) continue;
      byDay[_key(entry.day)] = (byDay[_key(entry.day)] ?? 0) + entry.minutes;
      if (entry.source == StudySource.plan) plan += entry.minutes;
      if (entry.source == StudySource.focus) focus += entry.minutes;
    }
    final last = DateTime(today.year, today.month, today.day);
    return StudyInsights._(
      [
        for (
          var day = DateTime(from.year, from.month, from.day);
          !day.isAfter(to);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          InsightDay(day, null, upcoming: day.isAfter(last)),
      ],
      byDay,
      plan,
      focus,
    );
  }

  final List<InsightDay> days;
  final Map<String, int> _minutes;
  final int planMinutes, focusMinutes;

  static String _key(DateTime day) => '${day.year}-${day.month}-${day.day}';

  int minutesOn(DateTime day) => _minutes[_key(day)] ?? 0;
  int get totalMinutes => _minutes.values.fold(0, (total, m) => total + m);
  int get studiedDays => _minutes.values.where((m) => m > 0).length;
  int get elapsedDays => days.where((day) => !day.upcoming).length;
  bool get hasData => totalMinutes > 0;

  DayState state(InsightDay day) => day.upcoming
      ? DayState.upcoming
      : minutesOn(day.day) > 0
      ? DayState.hit
      : DayState.logged;
}
