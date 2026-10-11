import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/study_log.dart';
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

  /// Records [minutes] of study for the user's today from a finished Focus
  /// phase that started at [startedAt]. Counts toward the day's study minutes
  /// and streaks; the server won't credit the same minutes again for a plan
  /// block checked off as done.
  Future<void> logStudyMinutes(int minutes, {required DateTime startedAt});

  /// Logged study, newest first: by hand, from Focus, or from plan blocks.
  Future<List<StudyLog>> getStudyLog(DateTime from, DateTime to);
}
