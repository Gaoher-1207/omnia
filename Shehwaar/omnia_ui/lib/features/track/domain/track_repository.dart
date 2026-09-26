import 'package:omnia_ui/features/track/domain/wellbeing.dart';

/// Per-day activity and sleep. Saves replace the whole day.
abstract interface class TrackRepository {
  /// Zeroes when nothing is stored for [day].
  Future<ActivityDay> getActivity(DateTime day);
  Future<ActivityDay> saveActivity(ActivityDay activity);

  /// Null when no sleep is logged for the night ending on [day].
  Future<SleepEntry?> getSleep(DateTime day);
  Future<SleepEntry> saveSleep(SleepEntry entry);
  Future<void> deleteSleep(DateTime day);
}
