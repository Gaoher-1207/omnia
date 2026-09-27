import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';

/// One signed-in user's latest suggestion. The server owns dates and storage.
class PlanController extends ChangeNotifier {
  PlanController(this._repository);
  final PlanRepository _repository;
  DailyPlan? _plan;
  Object? _error;
  bool _busy = false, _loaded = false, _disposed = false;

  DailyPlan? get plan => _plan;
  Object? get error => _error;
  bool get busy => _busy;
  bool get loaded => _loaded;

  Future<void> load() => _run(_repository.getToday);
  Future<void> generate() => _run(_repository.generate);

  Future<void> _run(Future<DailyPlan?> Function() operation) async {
    if (_busy || _disposed) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await operation();
      if (!_disposed) {
        _plan = result;
        _loaded = true;
      }
    } catch (failure) {
      if (!_disposed) _error = failure;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PlanScope extends InheritedNotifier<PlanController> {
  const PlanScope({
    super.key,
    required PlanController controller,
    required super.child,
  }) : super(notifier: controller);
  static PlanController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanScope>()!.notifier!;
}
