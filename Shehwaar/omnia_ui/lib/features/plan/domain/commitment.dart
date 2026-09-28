import 'package:omnia_ui/core/api/json.dart';

class Commitment {
  Commitment.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      category = json['category'] as String,
      kind = json['kind'] as String,
      weekdays = List<int>.unmodifiable(json['weekdays'] ?? []),
      day = json['day'] == null ? null : parseDay(json['day'] as String),
      startMinutes = json['start_minutes'] as int,
      endMinutes = json['end_minutes'] as int,
      enabled = json['enabled'] as bool;

  final String id, title, category, kind;
  final List<int> weekdays;
  final DateTime? day;
  final int startMinutes, endMinutes;
  final bool enabled;

  bool appliesOn(DateTime selected) =>
      enabled &&
      (kind == 'one_off'
          ? day != null && formatDay(day!) == formatDay(selected)
          : weekdays.contains(selected.weekday - 1));
}

class CommitmentDraft {
  const CommitmentDraft({
    required this.title,
    required this.category,
    required this.kind,
    required this.weekdays,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    required this.enabled,
  });

  final String title, category, kind;
  final List<int> weekdays;
  final DateTime? day;
  final int startMinutes, endMinutes;
  final bool enabled;

  bool appliesOn(DateTime selected) =>
      enabled &&
      (kind == 'one_off'
          ? day != null && formatDay(day!) == formatDay(selected)
          : weekdays.contains(selected.weekday - 1));

  Map<String, Object?> toJson() => {
    'title': title.trim(),
    'category': category,
    'kind': kind,
    'weekdays': kind == 'recurring' ? weekdays : <int>[],
    'day': kind == 'one_off' && day != null ? formatDay(day!) : null,
    'start_minutes': startMinutes,
    'end_minutes': endMinutes,
    'enabled': enabled,
  };
}

class FreeInterval {
  FreeInterval.fromJson(Map<String, dynamic> json)
    : startMinutes = json['start_minutes'] as int,
      endMinutes = json['end_minutes'] as int;
  final int startMinutes, endMinutes;
}

class DayAvailability {
  DayAvailability.fromJson(Map<String, dynamic> json)
    : day = parseDay(json['day'] as String),
      startMinutes = json['planning_start_minutes'] as int,
      endMinutes = json['planning_end_minutes'] as int,
      commitments = List.unmodifiable(
        asMapList(json['commitments']).map(Commitment.fromJson),
      ),
      freeIntervals = List.unmodifiable(
        asMapList(json['free_intervals']).map(FreeInterval.fromJson),
      );

  final DateTime day;
  final int startMinutes, endMinutes;
  final List<Commitment> commitments;
  final List<FreeInterval> freeIntervals;
}
