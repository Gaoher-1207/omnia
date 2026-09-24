import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';

import 'support/fake_backend.dart';

void phoneSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  testWidgets('First run advances, swipes back, and continues to sign-in', (tester) async {
    phoneSize(tester, const Size(430, 932));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OmniaApp(dependencies: FakeBackend(signedIn: false).dependencies()));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(find.text('Everything. One plan.'), findsOneWidget);
    expect(find.byType(OmniaMark), findsOneWidget);
    expect(find.bySemanticsLabel('Onboarding page 1 of 2'), findsOneWidget);

    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();
    expect(find.text('One plan that adapts'), findsOneWidget);
    expect(find.bySemanticsLabel('Onboarding page 2 of 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('GET STARTED').hitTestable(), findsOneWidget);
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('GET STARTED').hitTestable(), findsOneWidget);
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(Navigator.of(tester.element(find.byType(AuthPage))).canPop(), isFalse);
    expect(tester.takeException(), isNull);

    // Signed-out visitors see onboarding again in a fresh app instance.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(OmniaApp(dependencies: FakeBackend(signedIn: false).dependencies()));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('Registering signs in, stores the token and survives a restart', (tester) async {
    phoneSize(tester, const Size(430, 1100));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend(signedIn: false);
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SKIP →'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'What should we call you?'), 'Riya');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'riya@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'long-enough-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.textContaining('Riya.'), findsOneWidget);
    expect(backend.tokens.token, isNotNull, reason: 'token saved for the next launch');

    // A fresh launch restores the session without signing in again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Wrong password shows the server message; an expired session returns to sign-in', (tester) async {
    phoneSize(tester, const Size(430, 1100));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend();
    await tester.pumpWidget(OmniaApp(dependencies: backend.dependencies()));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);

    backend.expireSessions();
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Your session ended. Please sign in again.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'sam@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Debug preview follows the selected theme and returns to Settings', (tester) async {
    phoneSize(tester, const Size(430, 932));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OmniaApp(dependencies: FakeBackend().dependencies()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Preview onboarding'), 200);
    await tester.tap(find.text('Preview onboarding'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(OnboardingPage))).brightness, Brightness.dark);
    await tester.tap(find.text('SKIP →'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Onboarding is scrollable without overflow in ${brightness.name}', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final scenario in [
        (size: const Size(320, 568), scale: 1.0),
        (size: const Size(360, 640), scale: 1.0),
        (size: const Size(430, 932), scale: 1.0),
        (size: const Size(320, 568), scale: 2.0),
        (size: const Size(740, 360), scale: 1.0),
      ]) {
        phoneSize(tester, scenario.size);
        // Recreate the app between sizes, including its page/scroll state.
        await tester.pumpWidget(const SizedBox());
        var skipped = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scenario.scale),
                padding: const EdgeInsets.only(top: 24, bottom: 16),
              ),
              child: child!,
            ),
            home: OnboardingPage(onSkip: () => skipped = true),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('GET STARTED'),
          160,
          scrollable: find
              .descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Scrollable))
              .first,
        );
        await tester.ensureVisible(find.text('GET STARTED'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();
        expect(find.text('One plan that adapts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('SKIP →'));
        await tester.pumpAndSettle();
        expect(skipped, isTrue);
      }
    });
  }
}
