import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/domain/commitment_repository.dart';

class ApiCommitmentRepository implements CommitmentRepository {
  ApiCommitmentRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Commitment>> list() async => [
    for (final item in asMapList(await _api.get('/commitments')))
      Commitment.fromJson(item),
  ];

  @override
  Future<DayAvailability> availability({DateTime? day}) async =>
      DayAvailability.fromJson(
        asMap(
          await _api.get(
            '/commitments/availability',
            query: {'day': day == null ? null : formatDay(day)},
          ),
        ),
      );

  @override
  Future<Commitment> save(CommitmentDraft draft, {String? id}) async =>
      Commitment.fromJson(
        asMap(
          id == null
              ? await _api.post('/commitments', body: draft.toJson())
              : await _api.put('/commitments/$id', body: draft.toJson()),
        ),
      );

  @override
  Future<void> delete(String id) async {
    await _api.delete('/commitments/$id');
  }
}
