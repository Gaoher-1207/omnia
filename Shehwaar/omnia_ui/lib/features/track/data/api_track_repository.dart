import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

/// `/api/activity/{day}` and `/api/sleep/{day}`. Both PUTs replace the whole
/// day, so every field is always sent.
class ApiTrackRepository implements TrackRepository {
  ApiTrackRepository(this._api);
  final ApiClient _api;

  @override
  Future<ActivityDay> getActivity(DateTime day) async =>
      activityFromApi(asMap(await _api.get('/activity/${formatDay(day)}')));

  @override
  Future<ActivityDay> saveActivity(ActivityDay activity) async =>
      activityFromApi(
        asMap(
          await _api.put(
            '/activity/${formatDay(activity.day)}',
            body: activityToApi(activity),
          ),
        ),
      );

  @override
  Future<SleepEntry?> getSleep(DateTime day) async =>
      sleepFromApi(asMap(await _api.get('/sleep/${formatDay(day)}')));

  @override
  Future<SleepEntry> saveSleep(SleepEntry entry) async => sleepFromApi(
    asMap(
      await _api.put('/sleep/${formatDay(entry.day)}', body: sleepToApi(entry)),
    ),
  )!;

  @override
  Future<void> deleteSleep(DateTime day) =>
      _api.delete('/sleep/${formatDay(day)}');
}

ActivityDay activityFromApi(Map<String, dynamic> json) => ActivityDay(
  day: parseDay(json['day'] as String),
  steps: json['steps'] as int,
  workoutDone: json['workout_done'] as bool,
  workoutMinutes: json['workout_minutes'] as int,
  workoutType: json['workout_type'] as String?,
);

/// `ActivityUpsert`: all four fields, since the PUT replaces the day.
Map<String, Object?> activityToApi(ActivityDay activity) {
  final day = activity.normalized();
  return {
    'steps': day.steps,
    'workout_done': day.workoutDone,
    'workout_minutes': day.workoutMinutes,
    'workout_type': day.workoutType,
  };
}

/// Null for the server's "not logged" placeholder.
SleepEntry? sleepFromApi(Map<String, dynamic> json) => json['logged'] == false
    ? null
    : SleepEntry(
        day: parseDay(json['day'] as String),
        durationMinutes: json['duration_minutes'] as int,
        quality: json['quality'] as int?,
        bedtime: json['bedtime'] as String?,
        wakeTime: json['wake_time'] as String?,
      );

/// `SleepUpsert`: all four fields, bedtime and wake time passed through.
Map<String, Object?> sleepToApi(SleepEntry entry) => {
  'duration_minutes': entry.durationMinutes,
  'quality': entry.quality,
  'bedtime': entry.bedtime,
  'wake_time': entry.wakeTime,
};
