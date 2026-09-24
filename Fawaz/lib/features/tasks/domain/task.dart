import 'package:omnia_ui/core/models/omnia_category.dart';

enum TaskPriority { low, normal, high }

const _unchanged = Object();

class Task {
  Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.description,
    this.completed = false,
    this.priority = TaskPriority.normal,
    this.dueAt,
    this.estimatedDuration,
    this.category = OmniaCategory.tasks,
  }) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Task id and title must not be empty.');
    }
    if (estimatedDuration != null && estimatedDuration!.isNegative) {
      throw ArgumentError.value(estimatedDuration, 'estimatedDuration');
    }
  }

  final String id, title;
  final String? description;
  final bool completed;
  final TaskPriority priority;
  final DateTime createdAt;
  final DateTime? dueAt;
  final Duration? estimatedDuration;
  final OmniaCategory category;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    completed: json['completed'] as bool? ?? false,
    priority: TaskPriority.values.byName(json['priority'] as String? ?? 'normal'),
    dueAt: json['dueAt'] == null ? null : DateTime.parse(json['dueAt'] as String),
    estimatedDuration: json['estimatedDurationSeconds'] == null ? null
        : Duration(seconds: json['estimatedDurationSeconds'] as int),
    category: OmniaCategory.values.byName(json['category'] as String? ?? 'tasks'),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description, 'completed': completed,
    'priority': priority.name, 'dueAt': dueAt?.toUtc().toIso8601String(),
    'estimatedDurationSeconds': estimatedDuration?.inSeconds,
    'category': category.name, 'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Omitted nullable fields are retained; explicit null clears them.
  Task copyWith({
    String? title,
    Object? description = _unchanged,
    bool? completed,
    TaskPriority? priority,
    Object? dueAt = _unchanged,
    Object? estimatedDuration = _unchanged,
    OmniaCategory? category,
  }) => Task(
    id: id, title: title ?? this.title, createdAt: createdAt,
    description: identical(description, _unchanged) ? this.description : description as String?,
    completed: completed ?? this.completed, priority: priority ?? this.priority,
    dueAt: identical(dueAt, _unchanged) ? this.dueAt : dueAt as DateTime?,
    estimatedDuration: identical(estimatedDuration, _unchanged)
        ? this.estimatedDuration : estimatedDuration as Duration?,
    category: category ?? this.category,
  );
}
