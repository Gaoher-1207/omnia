import 'package:omnia_ui/core/models/omnia_category.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// ponytail: Task has one dueAt, so a date without a time is stored as local
// midnight; add an explicit all-day flag to Task if midnight deadlines matter.
bool isAllDay(DateTime local) => local.hour == 0 && local.minute == 0;

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime local) =>
    '${_weekdays[local.weekday - 1]}, ${_months[local.month - 1]} ${local.day}';

String formatDue(DateTime dueAt) {
  final local = dueAt.toLocal();
  return isAllDay(local)
      ? formatDate(local)
      : '${formatDate(local)} · ${_two(local.hour)}:${_two(local.minute)}';
}

String formatDuration(Duration duration) {
  final hours = duration.inHours, minutes = duration.inMinutes % 60;
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

String priorityLabel(TaskPriority priority) => switch (priority) {
  TaskPriority.low => 'Low',
  TaskPriority.normal => 'Normal',
  TaskPriority.high => 'High',
};

String categoryLabel(OmniaCategory category) =>
    category.name[0].toUpperCase() + category.name.substring(1);
