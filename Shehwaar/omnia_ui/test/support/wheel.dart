import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/widgets/number_wheel.dart';

/// The [NumberWheel] named [label] (its screen-reader label).
Finder wheel(String label) => find.byWidgetPredicate(
  (widget) => widget is NumberWheel && widget.label == label,
);

/// Scrolls the wheel named [label] to [value], the way a fling settles.
Future<void> spinTo(WidgetTester tester, String label, int value) async {
  await tester.ensureVisible(wheel(label));
  await tester.pumpAndSettle();
  final numbers = tester.widget<NumberWheel>(wheel(label));
  final picker = tester.widget<CupertinoPicker>(
    find.descendant(of: wheel(label), matching: find.byType(CupertinoPicker)),
  );
  picker.scrollController!.jumpToItem(numbers.values.indexOf(value));
  await tester.pumpAndSettle();
}
