import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

/// Compares trusted plan times with the current instant in the profile zone.
/// It never treats an already-ended snapshot block as upcoming.
({DailyPlanItem item, bool inProgress})? nextUp(
  Dashboard dashboard,
  DailyPlan? plan,
  DateTime utcNow,
) {
  if (plan == null || !_sameDay(plan.date, dashboard.date)) return null;
  final local = utcNow.toUtc().add(
    Duration(minutes: dashboard.timezoneOffsetMinutes),
  );
  if (!_sameDay(local, dashboard.date)) return null;
  final minute = local.hour * 60 + local.minute;
  final remaining = plan.items.where((item) => _minutes(item.end) > minute).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  if (remaining.isEmpty) return null;
  final item = remaining.first;
  return (item: item, inProgress: _minutes(item.start) <= minute);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _minutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
