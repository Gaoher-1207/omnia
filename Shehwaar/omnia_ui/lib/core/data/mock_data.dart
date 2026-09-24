import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/revision_item.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';

/// Fixed demo data matching the existing September 23 sample day.
/// Dates are UTC fixtures, not device-clock-dependent scheduling.
abstract final class MockData {
  static const subjects = [
    Subject(id: 'subject-dbms', name: 'DBMS'),
  ];
  static List<Exam> get exams => [
    Exam(id: 'exam-dbms', subjectId: 'subject-dbms', title: 'DBMS exam',
        scheduledAt: DateTime.utc(2025, 10, 1)),
  ];
  static List<Task> get tasks => [
    Task(id: 'task-assignment', title: 'Complete Assignment',
        dueAt: DateTime.utc(2025, 9, 23, 11),
        estimatedDuration: const Duration(hours: 1),
        createdAt: DateTime.utc(2025, 9, 23)),
  ];
  static List<Goal> get goals => [
    Goal(id: 'goal-study', title: 'Study', currentValue: 135, targetValue: 240,
        unit: 'minutes', category: OmniaCategory.study),
    Goal(id: 'goal-tasks', title: 'Tasks', currentValue: 4, targetValue: 6,
        unit: 'tasks', category: OmniaCategory.tasks),
    Goal(id: 'goal-activity', title: 'Activity', currentValue: 6240, targetValue: 8000,
        unit: 'steps', category: OmniaCategory.activity),
    Goal(id: 'goal-sleep', title: 'Sleep', currentValue: 402, targetValue: 480,
        unit: 'minutes', category: OmniaCategory.sleep),
  ];
  static StudySession get revisionSession => StudySession(
    id: 'session-dbms-revision', subjectId: 'subject-dbms', examId: 'exam-dbms',
    title: 'DBMS Revision', startsAt: DateTime.utc(2025, 9, 23, 10),
    duration: const Duration(minutes: 45),
    revisionItems: const [
      RevisionItem(id: 'revision-normalization', title: 'Revise normalization'),
      RevisionItem(id: 'revision-sql', title: 'Practice SQL questions'),
      RevisionItem(id: 'revision-papers', title: 'Go through past papers'),
    ],
  );
}
