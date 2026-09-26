import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';

/// Opens the [SelectField] labelled [label] and chooses [option].
Future<void> pick(WidgetTester tester, String label, String option) async {
  final field = find.widgetWithText(PickerField, label);
  if (field.evaluate().isEmpty) {
    // Not built yet: further down a lazily built list.
    await tester.dragUntilVisible(
      field,
      find.byType(ListView).last,
      const Offset(0, -200),
    );
  }
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  if (find.text(option).evaluate().isEmpty) {
    await tester.dragUntilVisible(
      find.text(option),
      find.byType(ListView).last, // the sheet's options
      const Offset(0, -150),
    );
  }
  final choice = find.text(option).last;
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}
