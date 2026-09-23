import 'package:flutter/material.dart';

/// Local prototype state, owned by the app and retained across route changes.
class RevisionController extends ChangeNotifier {
  String _title = 'DBMS Revision';
  String get title => _title;
  final tasks = const [
    'Revise normalization',
    'Practice SQL questions',
    'Go through past papers',
  ];
  final List<bool> _checked = [false, false, false];
  bool isChecked(int index) => _checked[index];
  int get done => _checked.where((value) => value).length;

  void setChecked(int index, bool value) {
    _checked[index] = value;
    notifyListeners();
  }

  void markAll(bool value) {
    _checked.fillRange(0, _checked.length, value);
    notifyListeners();
  }

  void rename(String value) {
    if (value.trim().isEmpty) return;
    _title = value.trim();
    notifyListeners();
  }
}

class RevisionScope extends InheritedNotifier<RevisionController> {
  const RevisionScope({
    super.key,
    required RevisionController controller,
    required super.child,
  }) : super(notifier: controller);

  static RevisionController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevisionScope>()!.notifier!;
}
