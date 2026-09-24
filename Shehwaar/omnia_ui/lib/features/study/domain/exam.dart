class Exam {
  const Exam({
    required this.id, required this.subjectId,
    required this.title, required this.scheduledAt,
  });
  final String id, subjectId, title;
  final DateTime scheduledAt;

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
    id: json['id'] as String, subjectId: json['subjectId'] as String,
    title: json['title'] as String,
    scheduledAt: DateTime.parse(json['scheduledAt'] as String),
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'subjectId': subjectId, 'title': title,
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
  };
}
