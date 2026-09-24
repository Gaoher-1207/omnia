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
  // Goal deadlines are calendar dates, so they are local midnight rather than
  // UTC: a UTC midnight would display as the previous day west of Greenwich.
  static List<Goal> get goals => [
    Goal(id: 'goal-dbms-chapters', title: 'Finish DBMS chapters',
        description: 'Cover every chapter before the DBMS exam.',
        currentValue: 6, targetValue: 10, unit: 'chapters',
        category: OmniaCategory.study, deadline: DateTime(2025, 9, 30)),
    Goal(id: 'goal-incline-press', title: 'Incline Dumbbell Press',
        currentValue: 22.5, targetValue: 30, unit: 'kg',
        category: OmniaCategory.activity, deadline: DateTime(2025, 10, 30)),
    Goal(id: 'goal-final-project', title: 'Submit final-year project',
        category: OmniaCategory.tasks, deadline: DateTime(2025, 11, 10)),
    Goal(id: 'goal-books', title: 'Read 12 books this year',
        currentValue: 7, targetValue: 12, unit: 'books',
        category: OmniaCategory.habits, deadline: DateTime(2025, 12, 31)),
    Goal(id: 'goal-steps', title: 'Walk 10,000 steps a day',
        currentValue: 8200, targetValue: 10000, unit: 'steps',
        category: OmniaCategory.activity),
    Goal(id: 'goal-timetable', title: 'Set up a weekly study timetable',
        completed: true, category: OmniaCategory.study),
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
