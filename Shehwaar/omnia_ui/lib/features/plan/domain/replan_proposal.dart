import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

/// A backend-validated proposal. It is only a preview until explicitly applied.
class ReplanProposal {
  ReplanProposal.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      basePlanId = json['base_plan_id'] as String,
      baseRevision = json['base_revision'] as int,
      planDate = parseDay(json['plan_date'] as String),
      status = json['status'] as String,
      request = json['request'] as String,
      summary = json['summary'] as String,
      explanation = json['explanation'] as String,
      operations = List.unmodifiable(
        asMapList(json['operations']).map(ReplanOperation.fromJson),
      ),
      schedule = List.unmodifiable(
        asMapList(json['schedule']).map(DailyPlanItem.fromJson),
      ),
      warnings = List<String>.unmodifiable(json['warnings'] ?? []),
      validation = Map.unmodifiable(asMap(json['validation'])),
      createdAt = DateTime.parse(json['created_at'] as String),
      expiresAt = DateTime.parse(json['expires_at'] as String),
      appliedAt = json['applied_at'] == null
          ? null
          : DateTime.parse(json['applied_at'] as String),
      dismissedAt = json['dismissed_at'] == null
          ? null
          : DateTime.parse(json['dismissed_at'] as String);

  final String id, basePlanId, status, request, summary, explanation;
  final int baseRevision;
  final DateTime planDate, createdAt, expiresAt;
  final DateTime? appliedAt, dismissedAt;
  final List<ReplanOperation> operations;
  final List<DailyPlanItem> schedule;
  final List<String> warnings;
  final Map<String, dynamic> validation;

  bool get isPending => status == 'pending';
}

class ReplanOperation {
  ReplanOperation.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      itemKey = json['item_key'] as String,
      entityId = json['entity_id'] as String?,
      before = json['before'] == null
          ? null
          : Map.unmodifiable(asMap(json['before'])),
      after = json['after'] == null
          ? null
          : Map.unmodifiable(asMap(json['after'])),
      reason = json['reason'] as String;

  final String kind, itemKey, reason;
  final String? entityId;
  final Map<String, dynamic>? before, after;
}
