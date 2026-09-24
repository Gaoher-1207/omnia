import 'package:omnia_ui/core/data/in_memory_data_source.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/core/data/repository_exception.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

class MockStudyRepository implements StudyRepository {
  MockStudyRepository({
    Iterable<Subject>? subjects,
    Iterable<Exam>? exams,
    Iterable<StudySession>? sessions,
  }) : _subjects = InMemoryDataSource(subjects ?? MockData.subjects, idOf: (item) => item.id),
       _exams = InMemoryDataSource(exams ?? MockData.exams, idOf: (item) => item.id),
       _sessions = InMemoryDataSource(sessions ?? [MockData.revisionSession], idOf: (item) => item.id) {
    for (final exam in _exams.getAll()) {
      _subjects.get(exam.subjectId);
    }
    for (final session in _sessions.getAll()) {
      _validateSession(session);
    }
  }
  final InMemoryDataSource<Subject> _subjects;
  final InMemoryDataSource<Exam> _exams;
  final InMemoryDataSource<StudySession> _sessions;

  void _validateSession(StudySession session) {
    _subjects.get(session.subjectId);
    final examId = session.examId;
    if (examId != null && _exams.get(examId).subjectId != session.subjectId) {
      throw RepositoryException(RepositoryError.invalidReference, examId);
    }
  }

  @override
  Future<List<Subject>> getSubjects() async => _subjects.getAll();
  @override
  Future<List<Exam>> getExams() async => _exams.getAll();
  @override
  Future<List<StudySession>> getSessions() async => _sessions.getAll();
  @override
  Future<StudySession> getSession(String id) async => _sessions.get(id);
  @override
  Future<StudySession> updateSession(StudySession session) async {
    _validateSession(session);
    return _sessions.update(session);
  }
}
