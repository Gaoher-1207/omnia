import 'package:omnia_ui/features/plan/domain/commitment.dart';

abstract interface class CommitmentRepository {
  Future<List<Commitment>> list();
  Future<DayAvailability> availability({DateTime? day});
  Future<Commitment> save(CommitmentDraft draft, {String? id});
  Future<void> delete(String id);
}
