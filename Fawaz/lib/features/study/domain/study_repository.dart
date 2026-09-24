import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/revision_item.dart';
import 'package:omnia_ui/features/study/domain/study_plan.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

/// Study data owned by the backend (`/api/study/...`).
abstract interface class StudyRepository {
  Future<List<Subject>> getSubjects();
  Future<Subject> createSubject(String name, {String? color});
  Future<void> deleteSubject(String id);

  Future<List<Exam>> getExams();
  Future<Exam> createExam({
    required String subjectId,
    required String title,
    required DateTime date,
  });
  Future<void> deleteExam(String id);

  /// Backlog and revision topics, optionally for one subject.
  Future<List<RevisionItem>> getTopics({String? subjectId});
  Future<RevisionItem> createTopic({
    required String subjectId,
    required String title,
    bool revision = false,
    int minutes = 60,
  });
  Future<RevisionItem> setTopicDone(String id, bool done);
  Future<void> deleteTopic(String id);

  /// Persist time actually studied.
  Future<StudyLog> logSession({
    required int minutes,
    String? subjectId,
    String? topicId,
    bool completeTopic = false,
  });
  Future<void> deleteSession(String id);
  Future<List<StudyLog>> getSessions({DateTime? from, DateTime? to});

  Future<StudyPlan> getPlan({int days = 7});
}
