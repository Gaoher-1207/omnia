/// The day at a glance, as the server sees it: [date] and [greeting] are
/// worked out in the user's profile timezone, so the app shows them as given
/// rather than deciding "today" itself.
///
/// Only what Home and Track show so far; the backend's streaks, upcoming
/// tasks, study blocks and daily plan arrive with their own phases.
class Dashboard {
  const Dashboard({
    required this.date,
    required this.greeting,
    required this.displayName,
    required this.today,
    this.nextExam,
    this.sample = false,
  });

  /// A calendar day (local midnight), not an instant.
  final DateTime date;

  /// `morning`, `afternoon` or `evening`.
  final String greeting;
  final String displayName;
  final TodaySummary today;
  final NextExam? nextExam;

  /// Demo data, not the user's: screens label it as a sample.
  final bool sample;
}

/// Today's totals against the profile's daily targets. A target of 0 means
/// the user isn't tracking it.
class TodaySummary {
  const TodaySummary({
    required this.studyMinutes,
    required this.studyGoalMinutes,
    required this.steps,
    required this.stepGoal,
    required this.sleepGoalMinutes,
    this.sleepMinutes,
  });

  final int studyMinutes, studyGoalMinutes, steps, stepGoal, sleepGoalMinutes;

  /// Null when no sleep was logged for today, which is not the same as 0.
  final int? sleepMinutes;
}

class NextExam {
  const NextExam({
    required this.title,
    required this.subjectName,
    required this.date,
    required this.daysLeft,
  });
  final String title, subjectName;
  final DateTime date;

  /// From the server's today; 0 means the exam is today.
  final int daysLeft;
}
