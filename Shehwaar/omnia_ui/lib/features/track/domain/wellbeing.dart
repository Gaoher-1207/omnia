/// One day's activity (`ActivityOut`). The backend stores a whole day at a
/// time: saving replaces every field, so edits start from the stored day.
class ActivityDay {
  const ActivityDay({
    required this.day,
    this.steps = 0,
    this.workoutDone = false,
    this.workoutMinutes = 0,
    this.workoutType,
  });

  /// A calendar day (local midnight) from the server's calendar.
  final DateTime day;
  final int steps, workoutMinutes;
  final bool workoutDone;
  final String? workoutType;

  /// The backend's rule, applied before sending so the app shows what will
  /// be stored: a workout that wasn't done has no minutes or type.
  ActivityDay normalized() =>
      workoutDone ? this : ActivityDay(day: day, steps: steps);
}

/// The sleep for the night ending on [day] (`SleepOut` with `logged: true`).
/// Not logged is `null`, which is different from a logged 0.
class SleepEntry {
  const SleepEntry({
    required this.day,
    required this.durationMinutes,
    this.quality,
    this.bedtime,
    this.wakeTime,
  });

  final DateTime day;
  final int durationMinutes;

  /// 1 (awful) to 5 (great), if rated.
  final int? quality;

  /// `HH:MM:SS` exactly as the server sent them. The app doesn't edit these
  /// yet, so it sends them back unchanged instead of erasing them.
  final String? bedtime, wakeTime;
}

/// Activity over a date range, as stored. A day missing from [logged] was
/// never logged, which is different from a logged day with 0 steps or no
/// workout; nothing here is filled in or estimated.
class ActivityHistory {
  ActivityHistory({
    required this.from,
    required this.to,
    required this.stepGoal,
    required Iterable<ActivityDay> logged,
  }) : _logged = {for (final day in logged) _key(day.day): day};

  final DateTime from, to;
  final int stepGoal;
  final Map<String, ActivityDay> _logged;

  /// The stored day, or null when nothing was logged for [day].
  ActivityDay? on(DateTime day) => _logged[_key(day)];

  static String _key(DateTime day) => '${day.year}-${day.month}-${day.day}';
}
