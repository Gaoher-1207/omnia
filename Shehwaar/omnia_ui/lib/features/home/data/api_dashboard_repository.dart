import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

/// `GET /api/dashboard`: one call for everything Home and Track summarise.
class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository(this._api);
  final ApiClient _api;

  @override
  Future<Dashboard> getDashboard() async =>
      dashboardFromApi(asMap(await _api.get('/dashboard')));
}

/// Backend `DashboardOut` → [Dashboard].
Dashboard dashboardFromApi(Map<String, dynamic> json) {
  final today = asMap(json['today']);
  final exam = json['next_exam'] == null ? null : asMap(json['next_exam']);
  return Dashboard(
    date: parseDay(json['date'] as String),
    timezoneOffsetMinutes: json['timezone_offset_minutes'] as int? ?? 0,
    aiPlan: json['ai_plan'] == null
        ? null
        : DailyPlan.fromJson(asMap(json['ai_plan'])),
    greeting: json['greeting'] as String,
    displayName: json['display_name'] as String,
    today: TodaySummary(
      studyMinutes: today['study_minutes'] as int,
      studyGoalMinutes: today['study_goal_minutes'] as int,
      steps: today['steps'] as int,
      stepGoal: today['step_goal'] as int,
      sleepMinutes: today['sleep_minutes'] as int?,
      sleepGoalMinutes: today['sleep_goal_minutes'] as int,
    ),
    nextExam: exam == null
        ? null
        : NextExam(
            title: exam['title'] as String,
            subjectName: exam['subject_name'] as String,
            date: parseDay(exam['exam_date'] as String),
            daysLeft: exam['days_left'] as int,
          ),
  );
}
