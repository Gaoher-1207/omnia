import 'package:omnia_ui/core/api/json.dart';

/// A persisted suggestion, not an accepted schedule or a completion record.
class DailyPlan {
  DailyPlan.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      date = parseDay(json['plan_date'] as String),
      createdAt = DateTime.parse(json['created_at'] as String),
      source = json['source'] as String,
      isFallback = json['is_fallback'] as bool,
      summary = json['summary'] as String,
      validationVersion = json['validation_version'] as int? ?? 0,
      windowStart = json['window_start'] as String?,
      windowEnd = json['window_end'] as String?,
      items = List.unmodifiable(
        asMapList(json['items']).map(DailyPlanItem.fromJson),
      ),
      unscheduled = List.unmodifiable(
        asMapList(json['unscheduled'] ?? []).map(UnscheduledWork.fromJson),
      ),
      assumptions = List<String>.unmodifiable(json['assumptions'] ?? []),
      tips = List<String>.unmodifiable(json['tips'] ?? []),
      adjustments = List<String>.unmodifiable(json['adjustments'] ?? []);

  final String id, source, summary;
  final DateTime date, createdAt;
  final bool isFallback;
  final int validationVersion;
  final String? windowStart, windowEnd;
  final List<DailyPlanItem> items;
  final List<UnscheduledWork> unscheduled;
  final List<String> assumptions, tips, adjustments;
}

class DailyPlanItem {
  DailyPlanItem.fromJson(Map<String, dynamic> json)
    : start = json['start'] as String,
      end = json['end'] as String,
      category = json['category'] as String,
      title = json['title'] as String,
      detail = json['detail'] as String?,
      taskId = json['task_id'] as String?,
      subjectId = json['subject_id'] as String?;
  final String start, end, category, title;
  final String? detail, taskId, subjectId;
  int get minutes => _minutes(end) - _minutes(start);
  static int _minutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

class UnscheduledWork {
  UnscheduledWork.fromJson(Map<String, dynamic> json)
    : title = json['title'] as String,
      reason = json['reason'] as String,
      remainingMinutes = json['remaining_minutes'] as int;
  final String title, reason;
  final int remainingMinutes;
}
