import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

abstract interface class StudyRepository {
  Future<List<Subject>> getSubjects();
  Future<List<Exam>> getExams();
  Future<List<StudySession>> getSessions();
  Future<StudySession> getSession(String id);
  Future<StudySession> updateSession(StudySession session);
}
