import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/data/in_memory_data_source.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/core/data/repository_exception.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/revision_repository.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

/// Mock mode's study data: the sample subject and exam (days counted from
/// the sample day, [today]) and the demo revision session. Refusals are the
/// same [ApiException]s the backend sends, so screens behave alike.
class MockStudyRepository implements StudyRepository, RevisionRepository {
  MockStudyRepository({
    Iterable<Subject>? subjects,
    Iterable<Exam>? exams,
    Iterable<StudySession>? sessions,
    DateTime? today,
  }) : _today = today ?? MockData.dashboard.date,
       _subjects = InMemoryDataSource(
         subjects ?? MockData.subjects,
         idOf: (item) => item.id,
       ),
       _exams = InMemoryDataSource(
         exams ?? MockData.exams,
         idOf: (item) => item.id,
       ),
       _sessions = InMemoryDataSource(
         sessions ?? [MockData.revisionSession],
         idOf: (item) => item.id,
       ) {
    for (final exam in _exams.getAll()) {
      _subjects.get(exam.subjectId);
    }
    for (final session in _sessions.getAll()) {
      _subjects.get(session.subjectId);
      final examId = session.examId;
      if (examId != null && _exams.get(examId).subjectId != session.subjectId) {
        throw RepositoryException(RepositoryError.invalidReference, examId);
      }
    }
  }
  final DateTime _today;
  final InMemoryDataSource<Subject> _subjects;
  final InMemoryDataSource<Exam> _exams;
  final InMemoryDataSource<StudySession> _sessions;
  var _ids = 0;

  static const _notFound = ApiException(
    statusCode: 404,
    code: 'not_found',
    message: 'That item no longer exists.',
  );

  T _owned<T>(InMemoryDataSource<T> source, String id) {
    try {
      return source.get(id);
    } on RepositoryException {
      throw _notFound;
    }
  }

  void _checkUnique(String name, [String? id]) {
    if (_subjects.getAll().any((s) => s.name == name && s.id != id)) {
      throw const ApiException(
        statusCode: 409,
        code: 'conflict',
        message: 'You already have a subject with this name',
      );
    }
  }

  Exam _exam(String id, ExamDraft draft) => Exam(
    id: id,
    subjectId: draft.subjectId,
    subjectName: _owned(_subjects, draft.subjectId).name,
    title: draft.title,
    date: draft.date,
    notes: draft.notes,
    daysLeft: draft.date.difference(_today).inDays,
  );

  /// Stored exams carry the subject's current name and today's count.
  Exam _fresh(Exam exam) => _exam(
    exam.id,
    ExamDraft(
      subjectId: exam.subjectId,
      title: exam.title,
      date: exam.date,
      notes: exam.notes,
    ),
  );

  @override
  Future<List<Subject>> getSubjects() async =>
      [..._subjects.getAll()]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Subject> createSubject(String name) async {
    _checkUnique(name);
    return _subjects.create(Subject(id: 'subject-${++_ids}', name: name));
  }

  @override
  Future<Subject> renameSubject(String id, String name) async {
    _owned(_subjects, id);
    _checkUnique(name, id);
    return _subjects.update(Subject(id: id, name: name));
  }

  @override
  Future<void> deleteSubject(String id) async {
    _owned(_subjects, id);
    for (final exam in _exams.getAll().where((e) => e.subjectId == id)) {
      _exams.delete(exam.id);
    }
    _subjects.delete(id);
  }

  @override
  Future<List<Exam>> getExams() async => [
    for (final exam in _exams.getAll())
      if (!exam.date.isBefore(_today)) _fresh(exam),
  ]..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<Exam> createExam(ExamDraft draft) async =>
      _exams.create(_exam('exam-${++_ids}', draft));

  @override
  Future<Exam> updateExam(String id, ExamDraft draft) async {
    _owned(_exams, id);
    return _exams.update(_exam(id, draft));
  }

  @override
  Future<void> deleteExam(String id) async {
    _owned(_exams, id);
    _exams.delete(id);
  }

  @override
  Future<List<StudySession>> getSessions() async => _sessions.getAll();
  @override
  Future<StudySession> getSession(String id) async => _sessions.get(id);
  @override
  Future<StudySession> updateSession(StudySession session) async =>
      _sessions.update(session);
}
