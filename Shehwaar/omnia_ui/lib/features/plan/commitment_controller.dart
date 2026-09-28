import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/domain/commitment_repository.dart';

/// One account/session owns these manual commitments and date projections.
class CommitmentController extends ChangeNotifier {
  CommitmentController(this._repository);
  final CommitmentRepository _repository;
  List<Commitment> _rows = const [];
  DayAvailability? _availability;
  Object? _error;
  bool _loaded = false, _busy = false, _disposed = false;
  int _dateRequest = 0;
  DateTime? _requestedDate;

  List<Commitment> get rows => _rows;
  DayAvailability? get availability => _availability;
  Object? get error => _error;
  bool get loaded => _loaded;
  bool get busy => _busy;

  Future<void> loadAll({bool force = false}) async {
    if (_loaded && !force || _disposed) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.list();
      if (!_disposed) {
        _rows = result;
        _loaded = true;
      }
    } catch (error) {
      if (!_disposed) _error = error;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadForDate(DateTime? day, {bool force = false}) async {
    if (_disposed) return;
    if (!force && _availability != null && _requestedDate == day) return;
    _requestedDate = day;
    final request = ++_dateRequest;
    _availability = null;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.availability(day: day);
      if (!_disposed && request == _dateRequest) _availability = result;
    } catch (error) {
      if (!_disposed && request == _dateRequest) _error = error;
    } finally {
      if (!_disposed && request == _dateRequest) notifyListeners();
    }
  }

  Future<void> save(CommitmentDraft draft, {String? id}) async {
    await _repository.save(draft, id: id);
    await loadAll(force: true);
    await loadForDate(_requestedDate, force: true);
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await loadAll(force: true);
    await loadForDate(_requestedDate, force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_dateRequest;
    super.dispose();
  }
}

class CommitmentScope extends InheritedNotifier<CommitmentController> {
  const CommitmentScope({
    super.key,
    required CommitmentController controller,
    required super.child,
  }) : super(notifier: controller);

  static CommitmentController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommitmentScope>()?.notifier;
}
