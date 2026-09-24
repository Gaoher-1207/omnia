import 'package:omnia_ui/core/models/omnia_category.dart';

const _unchanged = Object();

/// A goal is either measurable — [currentValue] of [targetValue] [unit],
/// e.g. 22.5 of 30 kg — or completion-only, with no measurement at all
/// (all three null). Progress is always derived, never entered as a
/// percentage, so other modules can later report real quantities.
///
/// [completed] is the user's decision and is independent of progress: a goal
/// past its target stays open until marked done, and a goal can be done
/// short of it. Reopening keeps the real values.
class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.category,
    this.targetValue,
    this.unit,
    double? currentValue,
    this.completed = false,
    this.description,
    this.deadline,
  }) : currentValue = targetValue == null ? currentValue : currentValue ?? 0 {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Goal id and title must not be empty.');
    }
    final target = targetValue, current = this.currentValue;
    if (target == null) {
      if (unit != null || current != null) {
        throw ArgumentError('A completion-only goal has no value or unit.');
      }
    } else if (!target.isFinite || target <= 0 ||
        !current!.isFinite || current < 0 ||
        unit == null || unit!.trim().isEmpty) {
      throw ArgumentError(
          'A measurable goal needs a positive target, a non-negative value and a unit.');
    }
  }

  final String id, title;
  final String? description, unit;
  final double? currentValue, targetValue;
  final bool completed;
  final DateTime? deadline;
  final OmniaCategory category;

  bool get measurable => targetValue != null;

  /// Derived whole percent for display, capped at 100 past the target while
  /// [currentValue] keeps the real amount; null when completion-only.
  /// Rounded down so 100% means the target was actually reached.
  int? get percent => measurable
      ? (currentValue! * 100 / targetValue!).floor().clamp(0, 100)
      : null;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String, title: json['title'] as String,
    description: json['description'] as String?,
    currentValue: (json['currentValue'] as num?)?.toDouble(),
    targetValue: (json['targetValue'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    completed: json['completed'] as bool? ?? false,
    category: OmniaCategory.values.byName(json['category'] as String),
    deadline: json['deadline'] == null ? null : DateTime.parse(json['deadline'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'currentValue': currentValue, 'targetValue': targetValue, 'unit': unit,
    'completed': completed,
    'category': category.name, 'deadline': deadline?.toUtc().toIso8601String(),
  };

  /// Omitted nullable fields are retained; explicit null clears them. Clear
  /// all three measurement fields to make a goal completion-only.
  Goal copyWith({
    String? title, Object? description = _unchanged,
    Object? currentValue = _unchanged, Object? targetValue = _unchanged,
    Object? unit = _unchanged, bool? completed,
    OmniaCategory? category, Object? deadline = _unchanged,
  }) => Goal(
    id: id, title: title ?? this.title,
    description: identical(description, _unchanged) ? this.description : description as String?,
    currentValue: identical(currentValue, _unchanged) ? this.currentValue : currentValue as double?,
    targetValue: identical(targetValue, _unchanged) ? this.targetValue : targetValue as double?,
    unit: identical(unit, _unchanged) ? this.unit : unit as String?,
    completed: completed ?? this.completed,
    category: category ?? this.category,
    deadline: identical(deadline, _unchanged) ? this.deadline : deadline as DateTime?,
  );
}
