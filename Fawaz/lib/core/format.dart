/// Display helpers shared across screens.

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String longDate(DateTime day) => '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';

String hoursLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String thousands(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

double ratio(num value, num goal) =>
    goal <= 0 ? (value > 0 ? 1.0 : 0.0) : (value / goal).clamp(0.0, 1.0).toDouble();
