import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/domain/task_repository.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

/// Tasks stored by the backend (`/api/tasks`), scoped by the backend to the
/// signed-in user's token. The backend assigns ids, so always use the
/// returned entity. Failures surface as `ApiException` from [ApiClient].
class ApiTaskRepository implements TaskRepository {
  ApiTaskRepository(this._api);
  final ApiClient _api;

  /// The backend's largest page.
  static const _pageSize = 200;

  @override
  Future<List<Task>> getTasks() async {
    final tasks = <Task>[];
    var offset = 0;
    while (true) {
      final page = asMap(
        await _api.get('/tasks', query: {'limit': _pageSize, 'offset': offset}),
      );
      final items = asMapList(page['items']);
      tasks.addAll(items.map(taskFromApi));
      offset += items.length;
      if (items.isEmpty || offset >= (page['total'] as int)) return tasks;
    }
  }

  @override
  Future<Task> getTask(String id) async =>
      taskFromApi(asMap(await _api.get('/tasks/$id')));

  @override
  Future<Task> createTask(Task task) async =>
      taskFromApi(asMap(await _api.post('/tasks', body: taskToApi(task))));

  @override
  Future<Task> updateTask(Task task) async => taskFromApi(
    asMap(
      await _api.patch(
        '/tasks/${task.id}',
        body: {...taskToApi(task), 'status': task.completed ? 'done' : 'todo'},
      ),
    ),
  );

  @override
  Future<Task> setCompleted(String id, bool completed) async => taskFromApi(
    asMap(
      await _api.patch(
        '/tasks/$id',
        body: {'status': completed ? 'done' : 'todo'},
      ),
    ),
  );

  @override
  Future<void> deleteTask(String id) => _api.delete('/tasks/$id');
}

const _toApiPriority = {
  TaskPriority.low: 'low',
  TaskPriority.normal: 'medium',
  TaskPriority.high: 'high',
};

TaskPriority _fromApiPriority(String? value) => switch (value) {
  'low' => TaskPriority.low,
  'high' => TaskPriority.high,
  _ => TaskPriority.normal,
};

/// Backend JSON → app model. A due date without a time becomes local midnight,
/// which the UI already treats as "all day".
Task taskFromApi(Map<String, dynamic> json) {
  DateTime? dueAt;
  final dueDate = json['due_date'] as String?;
  if (dueDate != null) {
    final day = parseDay(dueDate);
    final dueTime = json['due_time'] as String?; // "HH:MM:SS"
    if (dueTime == null) {
      dueAt = day;
    } else {
      final parts = dueTime.split(':');
      dueAt = DateTime(
        day.year,
        day.month,
        day.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    }
  }
  final minutes = json['estimated_minutes'] as int?;
  final category = json['category'] as String? ?? 'tasks';
  return Task(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['notes'] as String?,
    completed: json['status'] == 'done',
    priority: _fromApiPriority(json['priority'] as String?),
    dueAt: dueAt,
    estimatedDuration: minutes == null ? null : Duration(minutes: minutes),
    category: OmniaCategory.values.asNameMap()[category] ?? OmniaCategory.tasks,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// App model → backend body. Never sends `id` or `status` (the server owns
/// ids; status goes through [ApiTaskRepository.setCompleted]/`updateTask`)
/// and never a user id: ownership comes from the token. Explicit nulls clear
/// optional fields on PATCH.
// ponytail: a due time of exactly 00:00 is sent as all-day, the same as the
// UI's isAllDay; add an all-day flag to Task if midnight deadlines matter.
Map<String, Object?> taskToApi(Task task) {
  final due = task.dueAt?.toLocal();
  final minutes = task.estimatedDuration?.inMinutes;
  return {
    'title': task.title,
    'notes': task.description,
    'priority': _toApiPriority[task.priority],
    'due_date': due == null ? null : formatDay(due),
    'due_time': due == null || isAllDay(due)
        ? null
        : '${due.hour.toString().padLeft(2, '0')}:'
              '${due.minute.toString().padLeft(2, '0')}',
    'estimated_minutes': minutes == null || minutes < 1 ? null : minutes,
    'category': task.category.name,
  };
}
