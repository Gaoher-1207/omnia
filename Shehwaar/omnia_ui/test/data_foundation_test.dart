import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/core/data/repository_exception.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/study/data/mock_study_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';
import 'package:omnia_ui/features/tasks/data/mock_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';

final notFound = throwsA(
  isA<RepositoryException>().having(
    (e) => e.code,
    'code',
    RepositoryError.notFound,
  ),
);

void main() {
  test('Task JSON round trip keeps every field', () {
    final task = Task(
      id: 't1',
      title: 'Read chapter 3',
      description: 'Joins',
      completed: true,
      priority: TaskPriority.high,
      dueAt: DateTime.utc(2025, 9, 24, 9, 30),
      estimatedDuration: const Duration(minutes: 40),
      category: OmniaCategory.study,
      createdAt: DateTime.utc(2025, 9, 23),
    );
    expect(Task.fromJson(task.toJson()).toJson(), task.toJson());
    final minimal = Task.fromJson({
      'id': 'x',
      'title': 'Y',
      'createdAt': '2025-09-23T00:00:00.000Z',
    });
    expect(minimal.priority, TaskPriority.normal);
    expect(minimal.dueAt, isNull);
  });

  test('Goal and StudySession JSON round trips', () {
    for (final goal in MockData.goals) {
      expect(Goal.fromJson(goal.toJson()).toJson(), goal.toJson());
    }
    final session = MockData.revisionSession;
    expect(StudySession.fromJson(session.toJson()).toJson(), session.toJson());
  });

  test('MockTaskRepository CRUD and completion', () async {
    final repo = MockTaskRepository();
    expect((await repo.getTasks()).map((t) => t.id), ['task-assignment']);

    final created = await repo.createTask(
      Task(
        id: 't2',
        title: 'Buy notebook',
        createdAt: DateTime.utc(2025, 9, 23),
      ),
    );
    expect(await repo.getTasks(), hasLength(2));
    expect(() => repo.createTask(created), throwsA(isA<RepositoryException>()));

    await repo.updateTask(
      created.copyWith(title: 'Buy 2 notebooks', description: 'A5'),
    );
    expect((await repo.getTask('t2')).title, 'Buy 2 notebooks');
    expect((await repo.getTask('t2')).description, 'A5');

    expect((await repo.setCompleted('t2', true)).completed, isTrue);
    expect((await repo.getTask('t2')).completed, isTrue);
    expect((await repo.setCompleted('t2', false)).completed, isFalse);

    await repo.deleteTask('t2');
    expect(await repo.getTasks(), hasLength(1));
    expect(() => repo.getTask('t2'), notFound);
    expect(() => repo.deleteTask('t2'), notFound);
  });

  test('RevisionController persists through StudyRepository', () async {
    final repo = MockStudyRepository();
    final revision = RevisionController(
      session: await repo.getSession('session-dbms-revision'),
      repository: repo,
    );
    expect(revision.tasks, hasLength(3));

    revision.setChecked(1, true);
    revision.rename('SQL Revision');
    await pumpEventQueue();

    final stored = await repo.getSession('session-dbms-revision');
    expect(stored.title, 'SQL Revision');
    expect(stored.revisionItems.map((i) => i.completed), [false, true, false]);
    expect(revision.done, 1);
  });
}
