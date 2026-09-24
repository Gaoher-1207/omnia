/// A block the backend planner scheduled (GET /study/plan).
class StudyBlock {
  const StudyBlock({
    required this.subjectId,
    required this.subjectName,
    required this.title,
    required this.minutes,
    required this.reason,
    this.backlogItemId,
  });
  final String subjectId, subjectName, title, reason;
  final String? backlogItemId;
  final int minutes;

  factory StudyBlock.fromJson(Map<String, dynamic> json) => StudyBlock(
    subjectId: json['subject_id'] as String,
    subjectName: json['subject_name'] as String,
    backlogItemId: json['backlog_item_id'] as String?,
    title: json['title'] as String,
    minutes: json['minutes'] as int,
    reason: json['reason'] as String,
  );
}

class StudyPlanDay {
  const StudyPlanDay({
    required this.date,
    required this.availableMinutes,
    required this.plannedMinutes,
    required this.blocks,
    required this.exams,
  });
  final DateTime date;
  final int availableMinutes, plannedMinutes;
  final List<StudyBlock> blocks;

  /// "Subject: exam title" for exams on this day.
  final List<String> exams;
}

class StudyPlan {
  const StudyPlan({
    required this.days,
    required this.unscheduledMinutes,
    required this.warnings,
  });
  final List<StudyPlanDay> days;
  final int unscheduledMinutes;
  final List<String> warnings;
}

/// A study session that already happened (logged time).
class StudyLog {
  const StudyLog({
    required this.id,
    required this.day,
    required this.minutes,
    this.subjectId,
    this.subjectName,
    this.backlogItemId,
    this.createdAt,
  });
  final String id;
  final DateTime day;
  final int minutes;
  final String? subjectId, subjectName, backlogItemId;
  final DateTime? createdAt;
}
