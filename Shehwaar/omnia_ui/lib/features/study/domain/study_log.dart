import 'package:omnia_ui/core/api/json.dart';

/// How study time was recorded.
enum StudySource {
  /// Logged by hand (or by another client).
  manual,

  /// A Focus phase that ran to the end.
  focus,

  /// A plan block checked off as done (or partly done, with minutes).
  plan,
}

/// One logged stretch of study (`SessionOut`).
class StudyLog {
  const StudyLog({
    required this.id,
    required this.day,
    required this.minutes,
    required this.source,
    this.subjectName,
  });

  final String id;
  final DateTime day;
  final int minutes;
  final StudySource source;
  final String? subjectName;
}

StudyLog studyLogFromApi(Map<String, dynamic> json) => StudyLog(
  id: json['id'] as String,
  day: parseDay(json['session_date'] as String),
  minutes: json['duration_minutes'] as int,
  source: switch (json['source']) {
    'focus' => StudySource.focus,
    'plan' => StudySource.plan,
    _ => StudySource.manual,
  },
  subjectName: (json['subject'] as Map<String, dynamic>?)?['name'] as String?,
);
