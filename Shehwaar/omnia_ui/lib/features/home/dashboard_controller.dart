import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';

/// One user's dashboard, shared by Home and Track. A failed reload keeps the
/// last good dashboard, which always belongs to this session's user.
class DashboardController extends ChangeNotifier {
  DashboardController(this._repository);
  final DashboardRepository _repository;

  Dashboard? _dashboard;
  bool _loading = false, _disposed = false;
  Object? _loadError;

  /// Null until the first successful load.
  Dashboard? get dashboard => _dashboard;
  bool get loading => _loading;
  Object? get loadError => _loadError;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      _dashboard = await _repository.getDashboard();
    } catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
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
}
