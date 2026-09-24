class Exam {
  const Exam({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.scheduledAt,
    this.subjectName,
    this.daysLeft,
  });
  final String id, subjectId, title;
  final DateTime scheduledAt;
  final String? subjectName;

  /// Days until the exam in the user's timezone, as computed by the backend.
  final int? daysLeft;

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
    id: json['id'] as String,
    subjectId: json['subjectId'] as String,
    title: json['title'] as String,
    scheduledAt: DateTime.parse(json['scheduledAt'] as String),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
  };
}
