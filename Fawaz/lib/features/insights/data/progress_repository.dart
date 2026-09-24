import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/insights/domain/progress.dart';

/// Streaks, history and achievements. The backend is the source of truth for
/// streak rules; the app only presents them.
class ProgressRepository {
  ProgressRepository(this._api);
  final ApiClient _api;

  Future<Progress> progress({int days = 14}) async {
    final json = asMap(await _api.get('/progress', query: {'days': days}));
    return Progress(
      date: parseDay(json['date'] as String),
      streaks: Streaks.fromJson(asMap(json['streaks'])),
      history: [for (final day in asMapList(json['history'])) DayProgress.fromJson(day)],
    );
  }

  Future<List<Achievement>> achievements() async => [
    for (final json in asMapList(await _api.get('/achievements'))) Achievement.fromJson(json),
  ];
}
