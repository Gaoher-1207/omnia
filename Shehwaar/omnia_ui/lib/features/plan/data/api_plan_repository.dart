import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/manual_plan_item.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';

class ApiPlanRepository implements PlanRepository {
  ApiPlanRepository(this._api, {this.replanTimeout = defaultReplanTimeout});
  final ApiClient _api;

  /// The backend bounds a proposal to REPLAN_TIMEOUT_SECONDS (45 s by
  /// default), then falls back to the rules planner or answers with a clear
  /// error; this leaves room for that and the network, and no more.
  static const defaultReplanTimeout = Duration(seconds: 60);
  final Duration replanTimeout;

  @override
  Future<DailyPlan?> getToday({DateTime? date}) async {
    try {
      return DailyPlan.fromJson(
        asMap(
          await _api.get(
            '/ai/daily-plan',
            query: {'date': date == null ? null : formatDay(date)},
          ),
        ),
      );
    } on ApiException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<DailyPlan> generate() async => DailyPlan.fromJson(
    asMap(
      await _api.post(
        '/ai/daily-plan',
        body: {'regenerate': true},
        timeout: const Duration(seconds: 150),
      ),
    ),
  );

  @override
  Future<DailyPlan> addItem(
    DateTime day,
    ManualPlanItemDraft draft, {
    int? baseRevision,
  }) async => DailyPlan.fromJson(
    asMap(
      await _api.post(
        '/ai/daily-plan/${formatDay(day)}/items',
        body: draft.toJson(baseRevision: baseRevision),
      ),
    ),
  );

  @override
  Future<DailyPlan> removeItem(
    DateTime day,
    String itemKey, {
    int? baseRevision,
  }) async => DailyPlan.fromJson(
    asMap(
      await _api.delete(
        '/ai/daily-plan/${formatDay(day)}/items/${Uri.encodeComponent(itemKey)}'
        '${baseRevision == null ? '' : '?base_revision=$baseRevision'}',
      ),
    ),
  );

  @override
  Future<ReplanProposal> createReplanProposal(
    String request, {
    DateTime? date,
  }) async => ReplanProposal.fromJson(
    asMap(
      await _api.post(
        '/ai/replan/proposals',
        body: {
          'request': request,
          if (date != null) 'plan_date': formatDay(date),
        },
        timeout: replanTimeout,
        timeoutMessage:
            'OmniAI took too long to prepare changes. Nothing was changed. '
            'Try again, or ask for something simpler.',
      ),
    ),
  );

  @override
  Future<ReplanProposal> getReplanProposal(String proposalId) async =>
      ReplanProposal.fromJson(
        asMap(await _api.get('/ai/replan/proposals/$proposalId')),
      );

  @override
  Future<DailyPlan> applyReplanProposal(String proposalId) async =>
      DailyPlan.fromJson(
        asMap(await _api.post('/ai/replan/proposals/$proposalId/apply')),
      );

  @override
  Future<DailyPlan> recordOutcome(
    DateTime day,
    String itemKey,
    String? status, {
    int? minutes,
  }) async {
    final path =
        '/ai/daily-plan/${formatDay(day)}/items/'
        '${Uri.encodeComponent(itemKey)}/outcome';
    return DailyPlan.fromJson(
      asMap(
        status == null
            ? await _api.delete(path)
            : await _api.put(
                path,
                body: {'status': status, 'minutes': ?minutes},
              ),
      ),
    );
  }

  @override
  Future<ReplanProposal> dismissReplanProposal(String proposalId) async =>
      ReplanProposal.fromJson(
        asMap(await _api.post('/ai/replan/proposals/$proposalId/dismiss')),
      );
}
