import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';

/// Session-owned snapshots. Null selection means the server's current local day.
class PlanController extends ChangeNotifier {
  PlanController(this._repository, {this.loadsWithDashboard = false});
  final PlanRepository _repository;
  final bool loadsWithDashboard;
  DailyPlan? _plan;
  DailyPlan? _todayPlan;
  DateTime? _todayDate;
  bool _todayLoaded = false;
  DateTime? _selectedDate;
  Object? _error;
  bool _busy = false, _loaded = false, _disposed = false;
  int _request = 0;
  final _editedPlans = <String>{};
  DailyPlan? get plan => _plan;
  DailyPlan? get todayPlan => _todayPlan;
  DateTime? get todayDate => _todayDate;
  bool get todayLoaded => _todayLoaded;
  DateTime? get selectedDate => _selectedDate;
  Object? get error => _error;
  bool get busy => _busy;
  bool get loaded => _loaded;
  bool get mayBeStale => _editedPlans.contains(_plan?.id);

  void markEdited() {
    if (_plan != null) _editedPlans.add(_plan!.id);
    if (!_disposed) notifyListeners();
  }

  /// The dashboard already fetched today's persisted suggestion. Reuse that
  /// snapshot for Home and the initial Plan tab without a second request.
  void seedToday(DateTime date, DailyPlan? candidate) {
    if (_disposed) return;
    if (candidate != null &&
        (candidate.date.year != date.year ||
            candidate.date.month != date.month ||
            candidate.date.day != date.day)) {
      return;
    }
    final newDay =
        _todayDate == null ||
        _todayDate!.year != date.year ||
        _todayDate!.month != date.month ||
        _todayDate!.day != date.day;
    if (newDay) _todayPlan = null;
    _todayDate = date;
    // An earlier dashboard response can finish after explicit generation.
    final keepNewer =
        !newDay &&
        _todayPlan != null &&
        (candidate == null ||
            _todayPlan!.createdAt.isAfter(candidate.createdAt));
    if (!keepNewer) _todayPlan = candidate;
    _todayLoaded = true;
    if (_selectedDate == null && !_busy) {
      _plan = _todayPlan;
      _loaded = true;
      _error = null;
    }
    notifyListeners();
  }

  void seedTodayError(Object failure) {
    if (_disposed || _loaded || _busy || _selectedDate != null) return;
    _error = failure;
    notifyListeners();
  }

  Future<void> selectDate(DateTime? date) {
    _selectedDate = date;
    if (date == null && _todayLoaded) {
      ++_request;
      _busy = false;
      _plan = _todayPlan;
      _loaded = true;
      _error = null;
      notifyListeners();
      return Future.value();
    }
    _plan = null;
    _loaded = false;
    return _run(() => _repository.getToday(date: date), replace: true);
  }

  Future<void> load() => _run(() => _repository.getToday(date: _selectedDate));
  Future<void> generate() => _run(_repository.generate);

  Future<void> _run(
    Future<DailyPlan?> Function() operation, {
    bool replace = false,
  }) async {
    if (_disposed || (_busy && !replace)) return;
    final request = ++_request;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await operation();
      if (!_disposed && request == _request) {
        _plan = result;
        _loaded = true;
        if (_selectedDate == null) {
          _todayPlan = result;
          _todayLoaded = true;
          if (result != null) _todayDate = result.date;
        }
      }
    } catch (failure) {
      if (!_disposed && request == _request) _error = failure;
    } finally {
      if (!_disposed && request == _request) {
        _busy = false;
        notifyListeners();
      }
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
  static PlanController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanScope>()?.notifier;
}
