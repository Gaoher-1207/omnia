import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/features/areas/areas_page.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';
import 'package:omnia_ui/features/assistant/widgets/ask_omnia_button.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com';
final button = find.byType(AskOmniaButton);
final nav = find.byKey(const ValueKey('physical-bottom-nav'));

Future<void> start(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  double textScale = 1,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (reducedMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final backend = FakeAuthBackend()
    ..addUser('Sam', sam, 'password-123', signedIn: true);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: nav, matching: find.text(name)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one floating button on each of the four tabs', (tester) async {
    await start(tester);
    for (final (name, page) in [
      ('Today', HomePage),
      ('Plan', PlanPage),
      ('Areas', AreasPage),
      ('Insights', InsightsPage),
    ]) {
      await openTab(tester, name);
      expect(find.byType(page), findsOneWidget, reason: name);
      expect(button, findsOneWidget, reason: name);
      expect(button.hitTestable(), findsOneWidget, reason: name);
    }
  });

  testWidgets('Today no longer has the Ask OmniAI card', (tester) async {
    await start(tester);
    final today = find.byType(HomePage);
    expect(
      find.descendant(of: today, matching: find.text('Ask OmniAI')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: today,
        matching: find.text('What should I prioritize tonight?'),
      ),
      findsNothing,
    );
    expect(find.text('Ask OmniAI'), findsOneWidget); // only the button
  });

  testWidgets('it opens Ask OmniAI, without a second button on top', (
    tester,
  ) async {
    await start(tester);
    await openTab(tester, 'Plan');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(button, findsNothing, reason: 'covered by the assistant screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsNothing);
    expect(button, findsOneWidget);
  });

  testWidgets('screens opened inside a tab hide it until you come back', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(button, findsNothing);
    // Another tab at its first page still has it.
    await openTab(tester, 'Areas');
    expect(button, findsOneWidget);
    await openTab(tester, 'Today');
    expect(button, findsNothing, reason: 'Settings is still open on Today');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
  });

  for (final (size, scale) in [
    (const Size(430, 932), 1.0),
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 2.0),
  ]) {
    testWidgets('sits above the navigation, on screen ($size, ${scale}x)', (
      tester,
    ) async {
      await start(tester, size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(button);
      final bar = tester.getRect(nav);
      expect(rect.bottom, lessThan(bar.top), reason: 'above the nav bar');
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width - 8));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, lessThan(size.width * .7), reason: 'compact');
      // The page's last item can scroll clear of it.
      final context = tester.element(find.byType(HomePage));
      expect(
        askOmniaClearance(context),
        greaterThanOrEqualTo(bar.top - rect.top),
      );
    });
  }

  testWidgets('a brief glint every few seconds, then still', (tester) async {
    await start(tester);
    final state = tester.state<AskOmniaButtonState>(button);
    expect(state.glintScheduled, isTrue);
    expect(state.glinting, isFalse);
    await tester.pump(AskOmniaButton.glintEvery);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.glinting, isTrue);
    // Still a readable, tappable button mid-glint.
    expect(button.hitTestable(), findsOneWidget);
    expect(find.text('Ask OmniAI'), findsOneWidget);
    await tester.pump(AskOmniaButton.glintLength);
    expect(state.glinting, isFalse);
  });

  testWidgets('reduced motion: no glint at all', (tester) async {
    await start(tester, reducedMotion: true);
    final state = tester.state<AskOmniaButtonState>(button);
    expect(state.glintScheduled, isFalse);
    await tester.pump(AskOmniaButton.glintEvery * 3);
    expect(state.glinting, isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
  });

  testWidgets('screen readers find one labelled button', (tester) async {
    await start(tester);
    expect(find.bySemanticsLabel('Ask OmniAI'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Ask OmniAI')),
      isSemantics(label: 'Ask OmniAI', isButton: true, hasTapAction: true),
    );
  });
}
