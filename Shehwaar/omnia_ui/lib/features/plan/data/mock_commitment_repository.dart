import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/domain/commitment_repository.dart';

/// Session-local manual commitments for sample mode; never calls an API.
class MockCommitmentRepository implements CommitmentRepository {
  final _rows = <Commitment>[];
  int _next = 0;

  @override
  Future<List<Commitment>> list() async => List.unmodifiable(_rows);

  @override
  Future<Commitment> save(CommitmentDraft draft, {String? id}) async {
    final row = Commitment.fromJson({
      ...draft.toJson(),
      'id': id ?? 'sample-${++_next}',
    });
    _rows.removeWhere((old) => old.id == row.id);
    _rows.add(row);
    return row;
  }

  @override
  Future<void> delete(String id) async =>
      _rows.removeWhere((row) => row.id == id);

  @override
  Future<DayAvailability> availability({DateTime? day}) async {
    final selected = day ?? DateTime.now();
    final applicable = _rows
        .where(
          (row) =>
              row.enabled &&
              (row.kind == 'one_off'
                  ? row.day != null &&
                        formatDay(row.day!) == formatDay(selected)
                  : row.weekdays.contains(selected.weekday - 1)),
        )
        .toList();
    final busy = [
      for (final row in applicable)
        (row.startMinutes.clamp(480, 1320), row.endMinutes.clamp(480, 1320)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final slot in busy) {
      if (slot.$1 >= slot.$2) continue;
      if (merged.isNotEmpty && slot.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, slot.$2 > last.$2 ? slot.$2 : last.$2));
      } else {
        merged.add(slot);
      }
    }
    final free = <Map<String, int>>[];
    var cursor = 480;
    for (final slot in merged) {
      if (cursor < slot.$1) {
        free.add({'start_minutes': cursor, 'end_minutes': slot.$1});
      }
      cursor = slot.$2;
    }
    if (cursor < 1320) free.add({'start_minutes': cursor, 'end_minutes': 1320});
    return DayAvailability.fromJson({
      'day': formatDay(selected),
      'planning_start_minutes': 480,
      'planning_end_minutes': 1320,
      'commitments': [
        for (final row in applicable)
          {
            ...CommitmentDraft(
              title: row.title,
              category: row.category,
              kind: row.kind,
              weekdays: row.weekdays,
              day: row.day,
              startMinutes: row.startMinutes,
              endMinutes: row.endMinutes,
              enabled: row.enabled,
            ).toJson(),
            'id': row.id,
          },
      ],
      'free_intervals': free,
    });
  }
}
