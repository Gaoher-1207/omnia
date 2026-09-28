/// Presentation only: backend HH:mm and minute offsets remain unchanged.
String formatPlanMinutes(int minutes, String format) {
  final hour = minutes ~/ 60;
  final minute = (minutes % 60).toString().padLeft(2, '0');
  if (format == '12h') {
    return '${hour % 12 == 0 ? 12 : hour % 12}:$minute ${hour < 12 ? 'AM' : 'PM'}';
  }
  return '${hour.toString().padLeft(2, '0')}:$minute';
}

String formatPlanTime(String value, String format) {
  final parts = value.split(':').map(int.parse).toList();
  return formatPlanMinutes(parts[0] * 60 + parts[1], format);
}
