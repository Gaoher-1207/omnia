import 'package:flutter/widgets.dart';

/// Server data for one screen: loading → data | error, keeping the last good
/// data on screen while a refresh runs.
class Loadable<T> extends ChangeNotifier {
  Loadable(this._loader);

  final Future<T> Function() _loader;
  T? _data;
  Object? _error;
  bool _loading = false, _disposed = false;
  int _run = 0;

  T? get data => _data;
  Object? get error => _error;
  bool get loading => _loading;
  bool get hasData => _data != null;

  Future<void> load() async {
    final run = ++_run;
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await _loader();
      if (run == _run) _data = result;
    } catch (error) {
      if (run == _run) _error = error;
    } finally {
      if (run == _run) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Replace the data after a successful mutation, without a round trip.
  void set(T value) {
    _data = value;
    _error = null;
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

/// Makes a controller available to the widgets below it.
class ControllerScope<T extends ChangeNotifier> extends InheritedNotifier<T> {
  const ControllerScope({
    super.key,
    required T controller,
    required super.child,
  }) : super(notifier: controller);

  static T of<T extends ChangeNotifier>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControllerScope<T>>()!.notifier!;

  static T read<T extends ChangeNotifier>(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ControllerScope<T>>()!.notifier!;
}
