import 'package:omnia_ui/features/tasks/domain/task.dart';

/// IDs are supplied by the caller for now. Always use returned entities: a
/// future API may assign a canonical ID or normalize other fields on creation.
abstract interface class TaskRepository {
  Future<List<Task>> getTasks();
  Future<Task> getTask(String id);
  Future<Task> createTask(Task task);
  Future<Task> updateTask(Task task);
  Future<Task> setCompleted(String id, bool completed);
  Future<void> deleteTask(String id);
}
