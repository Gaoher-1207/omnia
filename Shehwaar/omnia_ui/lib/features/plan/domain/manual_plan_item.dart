/// A block the user adds to a day's plan by hand. The server keeps it fixed:
/// planners work around it and never move it. For task and study blocks the
/// server takes the title from the linked task or subject.
class ManualPlanItemDraft {
  const ManualPlanItemDraft({
    required this.category,
    required this.startMinutes,
    required this.durationMinutes,
    required this.title,
    this.taskId,
    this.subjectId,
  });

  /// `task`, `study`, `fitness`, `break`, `recovery` or `other`.
  final String category;
  final int startMinutes, durationMinutes;
  final String title;
  final String? taskId, subjectId;

  int get endMinutes => startMinutes + durationMinutes;

  /// The latest minute a block may end on the same day (23:59).
  static const dayEnd = 24 * 60 - 1;

  static String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Map<String, Object?> toJson({int? baseRevision}) => {
    'category': category,
    'start': hhmm(startMinutes),
    'duration_minutes': durationMinutes,
    if (taskId == null && subjectId == null) 'title': title,
    'task_id': ?taskId,
    'subject_id': ?subjectId,
    'base_revision': ?baseRevision,
  };
}
