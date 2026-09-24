import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';

/// App-owned task state. The repository is the source of truth; this mirrors
/// it and applies the entities returned by each successful operation.
class TaskController extends ChangeNotifier {
  TaskController(this._repository);
  final TaskRepository _repository;

  List<Task> _tasks = const [];
  bool _loading = false, _loaded = false, _disposed = false;
  Object? _loadError;
  final _busy = <String>{};

  /// Open tasks first, then by due date (undated last), then newest.
  List<Task> get tasks => [..._tasks]..sort(_order);
  bool get loading => _loading;
  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  int get completedCount => _tasks.where((task) => task.completed).length;
  bool isBusy(String id) => _busy.contains(id);

  static int _order(Task a, Task b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    final ad = a.dueAt, bd = b.dueAt;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
    return b.createdAt.compareTo(a.createdAt);
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      _tasks = await _repository.getTasks();
      _loaded = true;
    } catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Mutations return false on failure; state is left as the repository had it.
  Future<bool> create(Task task) => _run(null, () async {
    final created = await _repository.createTask(task);
    _tasks = [..._tasks, created];
  });

  Future<bool> update(Task task) => _run(task.id, () async {
    _replace(await _repository.updateTask(task));
  });

  Future<bool> setCompleted(String id, bool completed) => _run(id, () async {
    _replace(await _repository.setCompleted(id, completed));
  });

  Future<bool> delete(String id) => _run(id, () async {
    await _repository.deleteTask(id);
    _tasks = [..._tasks.where((task) => task.id != id)];
  });

  void _replace(Task task) =>
      _tasks = [for (final t in _tasks) t.id == task.id ? task : t];

  /// Ignores a second operation on a task that already has one in flight.
  Future<bool> _run(String? id, Future<void> Function() operation) async {
    if (id != null && !_busy.add(id)) return false;
    _notify();
    try {
      await operation();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (id != null) _busy.remove(id);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class TaskScope extends InheritedNotifier<TaskController> {
  const TaskScope({
    super.key,
    required TaskController controller,
    required super.child,
  }) : super(notifier: controller);

  static TaskController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TaskScope>()!.notifier!;
}
