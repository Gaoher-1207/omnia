/// A topic to cover for a subject: a backlog chapter or a revision item.
/// Shown as a sub-task inside a study session.
class RevisionItem {
  const RevisionItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.subjectId,
    this.subjectName,
    this.estimatedMinutes = 60,
    this.isRevision = false,
  });
  final String id, title;
  final bool completed;
  final String? subjectId, subjectName;
  final int estimatedMinutes;

  /// Revision (review something known) rather than backlog (not yet covered).
  final bool isRevision;

  factory RevisionItem.fromJson(Map<String, dynamic> json) => RevisionItem(
    id: json['id'] as String,
    title: json['title'] as String,
    completed: json['completed'] as bool? ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
  };
  RevisionItem copyWith({String? title, bool? completed}) => RevisionItem(
    id: id,
    title: title ?? this.title,
    completed: completed ?? this.completed,
    subjectId: subjectId,
    subjectName: subjectName,
    estimatedMinutes: estimatedMinutes,
    isRevision: isRevision,
  );
}
