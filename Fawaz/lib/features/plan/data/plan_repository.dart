import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

/// Today's plan from the backend. The app never calls an AI provider itself:
/// the backend decides between the AI and the rule-based planner.
class PlanRepository {
  PlanRepository(this._api);
  final ApiClient _api;

  /// Null when no plan exists for today yet.
  Future<DailyPlan?> today() async {
    try {
      return dailyPlanFromApi(asMap(await _api.get('/ai/daily-plan')));
    } on ApiException catch (error) {
      if (error.isNotFound) return null;
      rethrow;
    }
  }

  /// Returns today's plan, generating one if needed. [regenerate] forces a
  /// fresh plan; [note] tells the planner about the user's day.
  Future<DailyPlan> generate({bool regenerate = false, String? note}) async =>
      dailyPlanFromApi(
        asMap(
          await _api.post(
            '/ai/daily-plan',
            body: {
              'regenerate': regenerate,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            },
            timeout: const Duration(seconds: 60),
          ),
        ),
      );
}

DailyPlan dailyPlanFromApi(Map<String, dynamic> json) => DailyPlan(
  id: json['id'] as String,
  date: parseDay(json['plan_date'] as String),
  source: json['source'] as String,
  isFallback: json['is_fallback'] as bool? ?? false,
  summary: json['summary'] as String,
  items: [for (final item in asMapList(json['items'])) DailyPlanItem.fromJson(item)],
  tips: [for (final tip in json['tips'] as List) '$tip'],
  adjustments: [for (final a in json['adjustments'] as List) '$a'],
);
