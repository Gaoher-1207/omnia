import 'package:omnia_ui/core/data/in_memory_data_source.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';

class MockTaskRepository implements TaskRepository {
  MockTaskRepository({Iterable<Task>? seed})
      : _source = InMemoryDataSource(seed ?? MockData.tasks, idOf: (task) => task.id);
  final InMemoryDataSource<Task> _source;

  @override
  Future<List<Task>> getTasks() async => _source.getAll();
  @override
  Future<Task> getTask(String id) async => _source.get(id);
  @override
  Future<Task> createTask(Task task) async => _source.create(task);
  @override
  Future<Task> updateTask(Task task) async => _source.update(task);
  @override
  Future<Task> setCompleted(String id, bool completed) async =>
      _source.update(_source.get(id).copyWith(completed: completed));
  @override
  Future<void> deleteTask(String id) async => _source.delete(id);
}
