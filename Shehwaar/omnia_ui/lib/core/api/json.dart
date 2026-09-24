/// Small JSON helpers shared by API repositories.
Map<String, dynamic> asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> asMapList(dynamic value) => [
  for (final item in value as List) Map<String, dynamic>.from(item as Map),
];

/// Backend dates are `YYYY-MM-DD` in the user's timezone; keep them as local
/// calendar dates (midnight) on the device.
DateTime parseDay(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
