import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';

/// Optional persisted-suggestion fixture. The existing mock timeline remains a
/// labelled visual sample; mock mode does not pretend to run a planner.
///
/// Blocks added by hand are kept in memory for the session, with the same
/// rules as the server: nothing moves, an overlap or a stale view is refused.
class MockPlanRepository implements PlanRepository {
  MockPlanRepository([this.plan, DateTime? today])
    : _today = today ?? MockData.dashboard.date;
  final DailyPlan? plan;
  final DateTime _today;
  final _days = <String, Map<String, dynamic>>{};
  int _keys = 0;

  @override
  Future<DailyPlan?> getToday({DateTime? date}) async {
    final stored = _days[formatDay(date ?? _today)];
    if (stored != null) return DailyPlan.fromJson(stored);
    return date == null || plan?.date == date ? plan : null;
  }

  @override
  Future<DailyPlan> generate() async =>
      plan ?? (throw StateError('Plan generation requires API mode.'));

  @override
  Future<DailyPlan> addItem(
    DateTime day,
    ManualPlanItemDraft draft, {
    int? baseRevision,
  }) async {
    final key = formatDay(day);
    final current = _days[key];
    if (baseRevision != null && current?['revision'] != baseRevision) {
      throw const ApiException(
        statusCode: 409,
        code: 'plan_stale',
        message: 'Your plan changed. Refresh it and try again.',
      );
    }
    if (draft.durationMinutes < 5 ||
        draft.endMinutes > ManualPlanItemDraft.dayEnd) {
      throw const ApiException(
        statusCode: 422,
        code: 'plan_item_invalid',
        message: 'The block must end by 23:59 on the same day.',
      );
    }
    final items = asMapList(current?['items'] ?? const []);
    for (final item in items) {
      if (draft.taskId != null && item['task_id'] == draft.taskId) {
        throw ApiException(
          statusCode: 422,
          code: 'plan_item_invalid',
          message:
              '${item['title']} is already in this plan at ${item['start']}.',
        );
      }
      final start = DailyPlanItem.minutesOf(item['start'] as String);
      final end = DailyPlanItem.minutesOf(item['end'] as String);
      if (draft.startMinutes < end && draft.endMinutes > start) {
        throw ApiException(
          statusCode: 409,
          code: 'plan_item_conflict',
          message:
              'This overlaps ${item['title']} (${item['start']}–${item['end']}). '
              'Nothing was moved; choose another time.',
        );
      }
    }
    final revision = (current?['revision'] as int? ?? 0) + 1;
    _days[key] = {
      'id': 'mock-plan-$key-$revision',
      'revision': revision,
      'plan_date': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'manual',
      'is_fallback': false,
      'summary': 'Blocks you added to this day.',
      'items': [
        ...items,
        {
          'item_key': 'mock-item-${++_keys}',
          'start': ManualPlanItemDraft.hhmm(draft.startMinutes),
          'end': ManualPlanItemDraft.hhmm(draft.endMinutes),
          'category': draft.category,
          'title': draft.title,
          'task_id': draft.taskId,
          'subject_id': draft.subjectId,
          'manual': true,
        },
      ]..sort((a, b) => (a['start'] as String).compareTo(b['start'] as String)),
    };
    return DailyPlan.fromJson(_days[key]!);
  }

  @override
  Future<DailyPlan> removeItem(
    DateTime day,
    String itemKey, {
    int? baseRevision,
  }) async {
    final key = formatDay(day);
    final current = _days[key];
    if (current == null) throw StateError('Removing blocks requires API mode.');
    if (baseRevision != null && current['revision'] != baseRevision) {
      throw const ApiException(
        statusCode: 409,
        code: 'plan_stale',
        message:
            'Your plan changed. Refresh it and try again; nothing was removed.',
      );
    }
    final items = asMapList(current['items']);
    if (!items.any((item) => item['item_key'] == itemKey)) {
      throw const ApiException(
        statusCode: 409,
        code: 'plan_item_stale',
        message: 'This block is no longer in the latest plan.',
      );
    }
    final revision = (current['revision'] as int) + 1;
    _days[key] = {
      ...current,
      'id': 'mock-plan-$key-$revision',
      'revision': revision,
      'items': [
        for (final item in items)
          if (item['item_key'] != itemKey) item,
      ],
    };
    return DailyPlan.fromJson(_days[key]!);
  }

  @override
  Future<Never> createReplanProposal(String request, {DateTime? date}) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> getReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> applyReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<Never> dismissReplanProposal(String proposalId) async =>
      throw StateError('Adaptive replanning requires API mode.');

  @override
  Future<DailyPlan> recordOutcome(
    DateTime day,
    String itemKey,
    String? status, {
    int? minutes,
  }) async {
    final stored = _days[formatDay(day)];
    if (stored == null) throw StateError('Plan outcomes require API mode.');
    for (final item in (stored['items'] as List).cast<Map<String, dynamic>>()) {
      if (item['item_key'] == itemKey) {
        item['outcome'] = status;
        item['outcome_minutes'] = status == 'partial' ? minutes : null;
      }
    }
    return DailyPlan.fromJson(stored);
  }
}
