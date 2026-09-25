import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/tasks/task_format.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Tuesday, September 23".
String formatLongDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';

/// "2h 15m", "4h", "0m".
String formatMinutes(int minutes) => formatDuration(Duration(minutes: minutes));

/// "6,240".
String formatCount(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// Progress toward a daily target; 0 when the target is 0 (not tracking).
double towards(int value, int target) =>
    target <= 0 ? 0 : (value / target).clamp(0.0, 1.0);

String examHeadline(NextExam exam) => switch (exam.daysLeft) {
  0 => 'Your ${exam.subjectName} exam is today.',
  1 => 'Your ${exam.subjectName} exam is tomorrow.',
  final days => 'Your ${exam.subjectName} exam is in $days days.',
};
