import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';

/// One user's dashboard, shared by Home and Track. A failed reload keeps the
/// last good dashboard, which always belongs to this session's user.
class DashboardController extends ChangeNotifier {
  DashboardController(this._repository);
  final DashboardRepository _repository;

  Dashboard? _dashboard;
  bool _again = false, _disposed = false;
  Future<void>? _pending;
  Object? _loadError;

  /// Null until the first successful load.
  Dashboard? get dashboard => _dashboard;
  bool get loading => _pending != null;

  /// Why the latest load failed, if it did.
  Object? get loadError => _loadError;

  /// Asked for while a load is running, it fetches once more afterwards: a
  /// caller that has just changed something on the server always gets a
  /// dashboard requested after that change.
  Future<void> load() {
    if (_pending != null) {
      _again = true;
      return _pending!;
    }
    return _pending = _loadUntilCurrent();
  }

  Future<void> _loadUntilCurrent() async {
    try {
      do {
        _again = false;
        _loadError = null;
        _notify();
        try {
          _dashboard = await _repository.getDashboard();
        } catch (error) {
          _loadError = error;
        }
      } while (_again && !_disposed);
    } finally {
      _pending = null;
      _notify();
    }
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

class DashboardScope extends InheritedNotifier<DashboardController> {
  const DashboardScope({
    super.key,
    required DashboardController controller,
    required super.child,
  }) : super(notifier: controller);

  static DashboardController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardScope>()!.notifier!;

  /// Read without subscribing (for callbacks).
  static DashboardController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DashboardScope>()!.notifier!;
}
