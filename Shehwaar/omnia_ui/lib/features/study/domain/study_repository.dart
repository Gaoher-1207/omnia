import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

/// One user's subjects and exams. Failures surface as [ApiException]
/// (field errors, "not found", a duplicate subject name…).
abstract interface class StudyRepository {
  /// By name.
  Future<List<Subject>> getSubjects();
  Future<Subject> createSubject(String name);
  Future<Subject> renameSubject(String id, String name);

  /// Also deletes the subject's exams.
  Future<void> deleteSubject(String id);

  /// Upcoming only (today or later), nearest first.
  Future<List<Exam>> getExams();
  Future<Exam> createExam(ExamDraft draft);
  Future<Exam> updateExam(String id, ExamDraft draft);
  Future<void> deleteExam(String id);
}
