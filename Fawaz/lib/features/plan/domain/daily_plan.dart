enum PlanCategory { study, task, fitness, recovery, other }

/// One scheduled block from the backend's daily planner.
class DailyPlanItem {
  const DailyPlanItem({
    required this.start,
    required this.end,
    required this.category,
    required this.title,
    this.detail,
    this.taskId,
    this.subjectId,
    this.isBreak = false,
  });

  /// `HH:MM`, 24-hour, in the user's timezone.
  final String start, end;
  final PlanCategory category;
  final String title;
  final String? detail, taskId, subjectId;

  /// Breaks (lunch etc.) share recovery styling but get their own icon.
  final bool isBreak;

  int get minutes => _toMinutes(end) - _toMinutes(start);

  factory DailyPlanItem.fromJson(Map<String, dynamic> json) {
    final raw = json['category'] as String;
    final category = switch (raw) {
      'study' => PlanCategory.study,
      'task' => PlanCategory.task,
      'fitness' => PlanCategory.fitness,
      'break' || 'recovery' => PlanCategory.recovery,
      _ => PlanCategory.other,
    };
    return DailyPlanItem(
      start: json['start'] as String,
      end: json['end'] as String,
      category: category,
      title: json['title'] as String,
      detail: json['detail'] as String?,
      taskId: json['task_id'] as String?,
      subjectId: json['subject_id'] as String?,
      isBreak: raw == 'break',
    );
  }
}

class DailyPlan {
  const DailyPlan({
    required this.id,
    required this.date,
    required this.source,
    required this.isFallback,
    required this.summary,
    required this.items,
    required this.tips,
    required this.adjustments,
  });

  final String id, source, summary;
  final DateTime date;
  final bool isFallback;
  final List<DailyPlanItem> items;
  final List<String> tips, adjustments;

  /// Honest label for who made the plan.
  String get sourceLabel => isFallback
      ? 'AI unavailable · rule-based plan'
      : source == 'rules'
      ? 'Rule-based planner'
      : 'AI planner';

  /// The item happening at [now] (`HH:MM`), else the next one, else null.
  DailyPlanItem? currentOrNext(String now) {
    for (final item in items) {
      if (item.end.compareTo(now) > 0) return item;
    }
    return null;
  }

  List<DailyPlanItem> upcoming(String now, {int limit = 3}) =>
      items.where((item) => item.end.compareTo(now) > 0).take(limit).toList();
}

int _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// `HH:MM` for the device clock (plans are compared as strings).
String nowHhmm([DateTime? now]) {
  final t = now ?? DateTime.now();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
