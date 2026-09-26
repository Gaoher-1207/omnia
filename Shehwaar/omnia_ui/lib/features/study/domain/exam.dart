/// An exam for one of the user's subjects, on a calendar day (no time).
class Exam {
  const Exam({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.title,
    required this.date,
    required this.daysLeft,
    this.notes,
  });
  final String id, subjectId, subjectName, title;

  /// A calendar day (local midnight), not an instant.
  final DateTime date;

  /// Days from the server's today (0 = today), so the device clock and time
  /// zone never decide it.
  final int daysLeft;
  final String? notes;
}

/// What a user enters to create or change an exam.
class ExamDraft {
  const ExamDraft({
    required this.subjectId,
    required this.title,
    required this.date,
    this.notes,
  });
  final String subjectId, title;
  final DateTime date;
  final String? notes;
}
