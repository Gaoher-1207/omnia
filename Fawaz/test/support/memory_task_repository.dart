import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';

/// A TaskRepository kept in memory, for controller and screen tests.
class MemoryTaskRepository implements TaskRepository {
  MemoryTaskRepository({Iterable<Task> seed = const []}) {
    for (final task in seed) {
      _items[task.id] = task;
    }
  }
  final _items = <String, Task>{};

  Task _get(String id) => _items[id] ?? (throw StateError('not found: $id'));

  @override
  Future<List<Task>> getTasks() async => _items.values.toList();
  @override
  Future<Task> getTask(String id) async => _get(id);
  @override
  Future<Task> createTask(Task task) async {
    if (_items.containsKey(task.id)) throw StateError('duplicate: ${task.id}');
    return _items[task.id] = task;
  }

  @override
  Future<Task> updateTask(Task task) async {
    _get(task.id);
    return _items[task.id] = task;
  }

  @override
  Future<Task> setCompleted(String id, bool completed) async =>
      _items[id] = _get(id).copyWith(completed: completed);
  @override
  Future<void> deleteTask(String id) async {
    _get(id);
    _items.remove(id);
  }
}
