import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';

class ApiPlanRepository implements PlanRepository {
  ApiPlanRepository(this._api);
  final ApiClient _api;

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
}
