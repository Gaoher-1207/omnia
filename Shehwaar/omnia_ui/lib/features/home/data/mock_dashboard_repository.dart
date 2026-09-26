import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';
import 'package:omnia_ui/features/track/data/mock_track_repository.dart';

/// The sample day, with today's steps and sleep read from [track] — the
/// same in-memory state the mock log screens write — like the real
/// dashboard reads the stored day.
class MockDashboardRepository implements DashboardRepository {
  MockDashboardRepository({Dashboard? dashboard, MockTrackRepository? track})
    : _dashboard = dashboard ?? MockData.dashboard,
      _track = track ?? MockTrackRepository();
  final Dashboard _dashboard;
  final MockTrackRepository _track;

  @override
  Future<Dashboard> getDashboard() async {
    final base = _dashboard, today = base.today;
    final activity = await _track.getActivity(base.date);
    final sleep = await _track.getSleep(base.date);
    return Dashboard(
      date: base.date,
      greeting: base.greeting,
      displayName: base.displayName,
      nextExam: base.nextExam,
      sample: base.sample,
      today: TodaySummary(
        studyMinutes: today.studyMinutes,
        studyGoalMinutes: today.studyGoalMinutes,
        steps: activity.steps,
        stepGoal: today.stepGoal,
        sleepMinutes: sleep?.durationMinutes,
        sleepGoalMinutes: today.sleepGoalMinutes,
      ),
    );
  }
}
