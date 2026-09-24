/// Common IANA timezones. Flutter doesn't expose the device's IANA name
/// without a native plugin, so sign-up preselects one whose UTC offset matches
/// the device, and the user can change it in Settings.
const commonTimezones = <String>[
  'Pacific/Honolulu',
  'America/Anchorage',
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Sao_Paulo',
  'Atlantic/Azores',
  'UTC',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Paris',
  'Africa/Lagos',
  'Africa/Cairo',
  'Europe/Athens',
  'Africa/Johannesburg',
  'Africa/Nairobi',
  'Europe/Moscow',
  'Asia/Riyadh',
  'Asia/Tehran',
  'Asia/Dubai',
  'Asia/Kabul',
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Kathmandu',
  'Asia/Dhaka',
  'Asia/Yangon',
  'Asia/Bangkok',
  'Asia/Jakarta',
  'Asia/Singapore',
  'Asia/Shanghai',
  'Asia/Manila',
  'Australia/Perth',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Adelaide',
  'Australia/Sydney',
  'Pacific/Auckland',
];

/// Standard (non-DST) offsets in minutes for [commonTimezones].
const _offsets = <String, int>{
  'Pacific/Honolulu': -600,
  'America/Anchorage': -540,
  'America/Los_Angeles': -480,
  'America/Denver': -420,
  'America/Chicago': -360,
  'America/New_York': -300,
  'America/Sao_Paulo': -180,
  'Atlantic/Azores': -60,
  'UTC': 0,
  'Europe/London': 0,
  'Europe/Berlin': 60,
  'Europe/Paris': 60,
  'Africa/Lagos': 60,
  'Africa/Cairo': 120,
  'Europe/Athens': 120,
  'Africa/Johannesburg': 120,
  'Africa/Nairobi': 180,
  'Europe/Moscow': 180,
  'Asia/Riyadh': 180,
  'Asia/Tehran': 210,
  'Asia/Dubai': 240,
  'Asia/Kabul': 270,
  'Asia/Karachi': 300,
  'Asia/Kolkata': 330,
  'Asia/Kathmandu': 345,
  'Asia/Dhaka': 360,
  'Asia/Yangon': 390,
  'Asia/Bangkok': 420,
  'Asia/Jakarta': 420,
  'Asia/Singapore': 480,
  'Asia/Shanghai': 480,
  'Asia/Manila': 480,
  'Australia/Perth': 480,
  'Asia/Tokyo': 540,
  'Asia/Seoul': 540,
  'Australia/Adelaide': 570,
  'Australia/Sydney': 600,
  'Pacific/Auckland': 720,
};

/// Best guess for this device. Checks the current offset, then one hour less
/// (in case daylight saving is active).
String guessTimezone([DateTime? now]) {
  final offset = (now ?? DateTime.now()).timeZoneOffset.inMinutes;
  for (final candidate in [offset, offset - 60]) {
    for (final zone in commonTimezones) {
      if (_offsets[zone] == candidate) return zone;
    }
  }
  return 'UTC';
}
