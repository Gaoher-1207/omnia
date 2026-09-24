import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/plan/data/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';

/// Today's plan, shared by Home and Plan.
class PlanController extends ChangeNotifier {
  PlanController(this._repository);
  final PlanRepository _repository;

  DailyPlan? _plan;
  Object? _error;
  bool _loaded = false, _loading = false, _generating = false, _disposed = false;

  DailyPlan? get plan => _plan;
  Object? get error => _error;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get generating => _generating;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _plan = await _repository.today();
      _loaded = true;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Creates today's plan, or a fresh one when a plan already exists.
  /// Rethrows so the caller can show the reason.
  Future<void> generate({String? note}) async {
    if (_generating) return;
    _generating = true;
    _notify();
    try {
      _plan = await _repository.generate(regenerate: _plan != null, note: note);
      _loaded = true;
      _error = null;
    } finally {
      _generating = false;
      _notify();
    }
  }

  /// Use a plan that arrived with the dashboard, without another request.
  void adopt(DailyPlan? plan) {
    if (_generating || _loading) return;
    _plan = plan;
    _loaded = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
