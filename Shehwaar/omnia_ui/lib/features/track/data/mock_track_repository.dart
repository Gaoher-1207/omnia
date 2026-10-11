import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/data/mock_data.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

/// In-memory days, seeded with the sample day. The mock dashboard reads the
/// same instance, so a mock log changes the mock Home and Track at once.
class MockTrackRepository implements TrackRepository {
  MockTrackRepository({
    Iterable<ActivityDay>? activity,
    Iterable<SleepEntry>? sleep,
  }) : _activity = {
         for (final day in activity ?? [MockData.activity])
           formatDay(day.day): day,
       },
       _sleep = {
         for (final entry in sleep ?? [MockData.sleep])
           formatDay(entry.day): entry,
       };
  final Map<String, ActivityDay> _activity;
  final Map<String, SleepEntry> _sleep;

  @override
  Future<ActivityDay> getActivity(DateTime day) async =>
      _activity[formatDay(day)] ?? ActivityDay(day: day);

  @override
  Future<ActivityDay> saveActivity(ActivityDay activity) async =>
      _activity[formatDay(activity.day)] = activity.normalized();

  @override
  Future<ActivityHistory> activityHistory(DateTime from, DateTime to) async {
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    return ActivityHistory(
      from: first,
      to: last,
      stepGoal: stepGoal,
      logged: _activity.values.where(
        (day) => !day.day.isBefore(first) && !day.day.isAfter(last),
      ),
    );
  }

  /// The sample profile's target (see `MockData`).
  static const stepGoal = 8000;

  @override
  Future<SleepEntry?> getSleep(DateTime day) async => _sleep[formatDay(day)];

  @override
  Future<SleepEntry> saveSleep(SleepEntry entry) async =>
      _sleep[formatDay(entry.day)] = entry;

  @override
  Future<void> deleteSleep(DateTime day) async => _sleep.remove(formatDay(day));
}
