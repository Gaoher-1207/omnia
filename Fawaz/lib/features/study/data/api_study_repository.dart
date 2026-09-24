import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/revision_item.dart';
import 'package:omnia_ui/features/study/domain/study_plan.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

class ApiStudyRepository implements StudyRepository {
  ApiStudyRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Subject>> getSubjects() async => [
    for (final json in asMapList(await _api.get('/study/subjects')))
      Subject.fromJson(json),
  ];

  @override
  Future<Subject> createSubject(String name, {String? color}) async =>
      Subject.fromJson(
        asMap(
          await _api.post(
            '/study/subjects',
            body: {'name': name.trim(), 'color': color},
          ),
        ),
      );

  @override
  Future<void> deleteSubject(String id) => _api.delete('/study/subjects/$id');

  @override
  Future<List<Exam>> getExams() async => [
    for (final json in asMapList(await _api.get('/study/exams'))) _exam(json),
  ];

  @override
  Future<Exam> createExam({
    required String subjectId,
    required String title,
    required DateTime date,
  }) async => _exam(
    asMap(
      await _api.post(
        '/study/exams',
        body: {
          'subject_id': subjectId,
          'title': title.trim(),
          'exam_date': formatDay(date),
        },
      ),
    ),
  );

  @override
  Future<void> deleteExam(String id) => _api.delete('/study/exams/$id');

  @override
  Future<List<RevisionItem>> getTopics({String? subjectId}) async => [
    for (final json in asMapList(
      await _api.get('/study/backlog', query: {'subject_id': subjectId}),
    ))
      _topic(json),
  ];

  @override
  Future<RevisionItem> createTopic({
    required String subjectId,
    required String title,
    bool revision = false,
    int minutes = 60,
  }) async => _topic(
    asMap(
      await _api.post(
        '/study/backlog',
        body: {
          'subject_id': subjectId,
          'title': title.trim(),
          'kind': revision ? 'revision' : 'backlog',
          'estimated_minutes': minutes,
        },
      ),
    ),
  );

  @override
  Future<RevisionItem> setTopicDone(String id, bool done) async => _topic(
    asMap(
      await _api.patch(
        '/study/backlog/$id',
        body: {'status': done ? 'done' : 'pending'},
      ),
    ),
  );

  @override
  Future<void> deleteTopic(String id) => _api.delete('/study/backlog/$id');

  @override
  Future<StudyLog> logSession({
    required int minutes,
    String? subjectId,
    String? topicId,
    bool completeTopic = false,
  }) async => _log(
    asMap(
      await _api.post(
        '/study/sessions',
        body: {
          'duration_minutes': minutes,
          'subject_id': subjectId,
          'backlog_item_id': topicId,
          'complete_backlog_item': completeTopic && topicId != null,
        },
      ),
    ),
  );

  @override
  Future<void> deleteSession(String id) => _api.delete('/study/sessions/$id');

  @override
  Future<List<StudyLog>> getSessions({DateTime? from, DateTime? to}) async => [
    for (final json in asMapList(
      await _api.get(
        '/study/sessions',
        query: {
          'from': from == null ? null : formatDay(from),
          'to': to == null ? null : formatDay(to),
        },
      ),
    ))
      _log(json),
  ];

  @override
  Future<StudyPlan> getPlan({int days = 7}) async {
    final json = asMap(await _api.get('/study/plan', query: {'days': days}));
    return StudyPlan(
      unscheduledMinutes: json['unscheduled_minutes'] as int,
      warnings: [for (final w in json['warnings'] as List) '$w'],
      days: [
        for (final day in asMapList(json['days']))
          StudyPlanDay(
            date: parseDay(day['date'] as String),
            availableMinutes: day['available_minutes'] as int,
            plannedMinutes: day['planned_minutes'] as int,
            blocks: [
              for (final block in asMapList(day['blocks']))
                StudyBlock.fromJson(block),
            ],
            exams: [
              for (final exam in asMapList(day['exams']))
                '${exam['subject_name']}: ${exam['title']}',
            ],
          ),
      ],
    );
  }

  static Exam _exam(Map<String, dynamic> json) {
    final subject = asMap(json['subject']);
    return Exam(
      id: json['id'] as String,
      subjectId: subject['id'] as String,
      subjectName: subject['name'] as String,
      title: json['title'] as String,
      scheduledAt: parseDay(json['exam_date'] as String),
      daysLeft: json['days_left'] as int?,
    );
  }

  static RevisionItem _topic(Map<String, dynamic> json) {
    final subject = asMap(json['subject']);
    return RevisionItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['status'] == 'done',
      subjectId: subject['id'] as String,
      subjectName: subject['name'] as String,
      estimatedMinutes: json['estimated_minutes'] as int,
      isRevision: json['kind'] == 'revision',
    );
  }

  static StudyLog _log(Map<String, dynamic> json) {
    final subject = json['subject'] == null ? null : asMap(json['subject']);
    return StudyLog(
      id: json['id'] as String,
      day: parseDay(json['session_date'] as String),
      minutes: json['duration_minutes'] as int,
      subjectId: subject?['id'] as String?,
      subjectName: subject?['name'] as String?,
      backlogItemId: json['backlog_item_id'] as String?,
      createdAt: DateTime.tryParse('${json['created_at']}'),
    );
  }
}
