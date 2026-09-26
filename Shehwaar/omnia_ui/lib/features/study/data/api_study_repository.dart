import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

/// `/api/study/subjects` and `/api/study/exams`. The server scopes both to
/// the signed-in user and works out each exam's `days_left` in their time
/// zone.
class ApiStudyRepository implements StudyRepository {
  ApiStudyRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Subject>> getSubjects() async =>
      asMapList(await _api.get('/study/subjects')).map(subjectFromApi).toList();

  @override
  Future<Subject> createSubject(String name) async => subjectFromApi(
    asMap(await _api.post('/study/subjects', body: {'name': name})),
  );

  @override
  Future<Subject> renameSubject(String id, String name) async => subjectFromApi(
    asMap(await _api.patch('/study/subjects/$id', body: {'name': name})),
  );

  @override
  Future<void> deleteSubject(String id) => _api.delete('/study/subjects/$id');

  @override
  Future<List<Exam>> getExams() async =>
      asMapList(await _api.get('/study/exams')).map(examFromApi).toList();

  @override
  Future<Exam> createExam(ExamDraft draft) async => examFromApi(
    asMap(await _api.post('/study/exams', body: examToApi(draft))),
  );

  @override
  Future<Exam> updateExam(String id, ExamDraft draft) async => examFromApi(
    asMap(await _api.patch('/study/exams/$id', body: examToApi(draft))),
  );

  @override
  Future<void> deleteExam(String id) => _api.delete('/study/exams/$id');
}

Subject subjectFromApi(Map<String, dynamic> json) =>
    Subject(id: json['id'] as String, name: json['name'] as String);

/// `ExamOut` → [Exam]; the subject arrives embedded.
Exam examFromApi(Map<String, dynamic> json) {
  final subject = asMap(json['subject']);
  return Exam(
    id: json['id'] as String,
    subjectId: subject['id'] as String,
    subjectName: subject['name'] as String,
    title: json['title'] as String,
    date: parseDay(json['exam_date'] as String),
    daysLeft: json['days_left'] as int,
    notes: json['notes'] as String?,
  );
}

/// `ExamCreate` / `ExamUpdate`. An explicit null `notes` clears them.
Map<String, Object?> examToApi(ExamDraft draft) => {
  'subject_id': draft.subjectId,
  'title': draft.title,
  'exam_date': formatDay(draft.date),
  'notes': draft.notes,
};
