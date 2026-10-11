import 'package:omnia_ui/core/api/json.dart';

/// A persisted suggestion, not an accepted schedule or a completion record.
class DailyPlan {
  DailyPlan.fromJson(Map<String, dynamic> json)
    : planningStartMinutes = json['planning_start_minutes'] as int?,
      planningEndMinutes = json['planning_end_minutes'] as int?,
      revision = json['revision'] as int? ?? 1,
      id = json['id'] as String,
      date = parseDay(json['plan_date'] as String),
      createdAt = DateTime.parse(json['created_at'] as String),
      source = json['source'] as String,
      isFallback = json['is_fallback'] as bool,
      summary = json['summary'] as String,
      explanation = json['explanation'] is Map<String, dynamic>
          ? PlanExplanation.fromJson(
              json['explanation'] as Map<String, dynamic>,
            )
          : null,
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

  final int? planningStartMinutes, planningEndMinutes;
  final int revision;
  final String id, source, summary;
  final PlanExplanation? explanation;
  final DateTime date, createdAt;
  final bool isFallback;
  final int validationVersion;
  final String? windowStart, windowEnd;
  final List<DailyPlanItem> items;
  final List<UnscheduledWork> unscheduled;
  final List<String> assumptions, tips, adjustments;

  /// Older suggestions lack a typed explanation. Their original prose remains
  /// available in expanded details, while this uses only known item counts.
  PlanExplanation get displayExplanation {
    if (explanation != null) return explanation!;
    final tasks = items.where((item) => item.category == 'task').length;
    final study = items.where((item) => item.category == 'study').length;
    final reasons = <String>[
      if (tasks > 0) '$tasks task block${tasks == 1 ? '' : 's'} scheduled.',
      if (study > 0) '$study study block${study == 1 ? '' : 's'} scheduled.',
      if (unscheduled.isNotEmpty)
        '${unscheduled.length} item${unscheduled.length == 1 ? '' : 's'} not fully scheduled.',
    ];
    return PlanExplanation(
      headline: items.isEmpty
          ? 'No work was scheduled in this saved suggestion.'
          : 'This saved suggestion arranges work within its planning window.',
      keyReasons: reasons.take(3).toList(),
      supportingContext: const [],
    );
  }
}

class PlanExplanation {
  const PlanExplanation({
    required this.headline,
    required this.keyReasons,
    required this.supportingContext,
  });

  PlanExplanation.fromJson(Map<String, dynamic> json)
    : headline = json['headline'] as String,
      keyReasons = List<String>.unmodifiable(json['key_reasons'] ?? []),
      supportingContext = List<String>.unmodifiable(
        json['supporting_context'] ?? [],
      );

  final String headline;
  final List<String> keyReasons, supportingContext;
}

class DailyPlanItem {
  DailyPlanItem.fromJson(Map<String, dynamic> json)
    : itemKey = json['item_key'] as String?,
      start = json['start'] as String,
      end = json['end'] as String,
      category = json['category'] as String,
      title = json['title'] as String,
      detail = json['detail'] as String?,
      taskId = json['task_id'] as String?,
      subjectId = json['subject_id'] as String?,
      outcome = json['outcome'] as String?,
      outcomeMinutes = json['outcome_minutes'] as int?,
      manual = json['manual'] as bool? ?? false;
  final String start, end, category, title;

  /// Added by the user; planners keep it where it is.
  final bool manual;
  final String? itemKey;

  /// What the user recorded for this block: `done`, `partial`, `skipped`, or
  /// null when nothing was recorded (never assumed from the clock).
  final String? outcome;

  /// Minutes actually done, for a partly done block (null when not given).
  final int? outcomeMinutes;
  final String? detail, taskId, subjectId;
  int get minutes => _minutes(end) - _minutes(start);
  static int minutesOf(String time) => _minutes(time);
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
