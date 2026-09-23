import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';

void main() {
  testWidgets('Omnia opens Home and navigates through its main screens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OmniaApp());

    expect(find.text('Good morning,\nShew.'), findsOneWidget);
    await tester.tap(find.text("View today's plan"));
    await tester.pumpAndSettle();
    expect(find.text("Today's Plan"), findsOneWidget);

    await tester.tap(find.text('DBMS Revision'));
    await tester.pumpAndSettle();
    expect(find.text('Sub-tasks  0/3'), findsOneWidget);
    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(find.text('Sub-tasks  3/3'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.text('4 of 6'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await tester.pumpAndSettle();
    expect(find.text('Your week in perspective'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Good morning,\nShew.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
