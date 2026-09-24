import 'package:omnia_ui/core/models/omnia_category.dart';

const _unchanged = Object();

class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.targetValue,
    required this.unit,
    required this.category,
    this.currentValue = 0,
    this.description,
    this.deadline,
  }) {
    if (id.trim().isEmpty || title.trim().isEmpty || unit.trim().isEmpty) {
      throw ArgumentError('Goal id, title and unit must not be empty.');
    }
    if (!targetValue.isFinite || targetValue <= 0 ||
        !currentValue.isFinite || currentValue < 0) {
      throw ArgumentError('Goal target must be positive and current value non-negative.');
    }
  }

  final String id, title, unit;
  final String? description;
  final double currentValue, targetValue;
  final DateTime? deadline;
  final OmniaCategory category;

  double get progress => (currentValue / targetValue).clamp(0.0, 1.0);
  bool get completed => currentValue >= targetValue;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String, title: json['title'] as String,
    description: json['description'] as String?,
    currentValue: (json['currentValue'] as num? ?? 0).toDouble(),
    targetValue: (json['targetValue'] as num).toDouble(),
    unit: json['unit'] as String,
    category: OmniaCategory.values.byName(json['category'] as String),
    deadline: json['deadline'] == null ? null : DateTime.parse(json['deadline'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'currentValue': currentValue, 'targetValue': targetValue, 'unit': unit,
    'category': category.name, 'deadline': deadline?.toUtc().toIso8601String(),
  };

  Goal copyWith({
    String? title, Object? description = _unchanged,
    double? currentValue, double? targetValue, String? unit,
    OmniaCategory? category, Object? deadline = _unchanged,
  }) => Goal(
    id: id, title: title ?? this.title,
    description: identical(description, _unchanged) ? this.description : description as String?,
    currentValue: currentValue ?? this.currentValue,
    targetValue: targetValue ?? this.targetValue, unit: unit ?? this.unit,
    category: category ?? this.category,
    deadline: identical(deadline, _unchanged) ? this.deadline : deadline as DateTime?,
  );
}
