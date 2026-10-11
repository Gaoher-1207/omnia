import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_store.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';

import 'support/fake_auth_backend.dart';

void phoneSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  testWidgets('First run advances, swipes back, and skips into the main app', (
    tester,
  ) async {
    phoneSize(tester, const Size(430, 932));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const OmniaApp());
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(find.text('Everything. One plan.'), findsOneWidget);
    expect(find.byType(OmniaMark), findsOneWidget);
    expect(find.bySemanticsLabel('Onboarding page 1 of 2'), findsOneWidget);

    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();
    expect(find.text('How Omnia works'), findsOneWidget);
    for (final title in [
      'Bring it together',
      'Get a plan for today',
      'Stay in control',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    // The placeholder copy is gone for good.
    expect(find.textContaining('Next onboarding page'), findsNothing);
    expect(find.textContaining('reserved for the next'), findsNothing);
    expect(find.byType(HomePage), findsNothing);
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
    await tester.tap(find.text('SKIP →'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(HomePage))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);

    // Without a store nothing is saved: a fresh app starts with the intro.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const OmniaApp());
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  for (final exit in ['SKIP →', 'ENTER OMNIA']) {
    testWidgets('$exit saves completion; the next launch opens the app', (
      tester,
    ) async {
      phoneSize(tester, const Size(430, 932));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryOnboardingStore();
      await tester.pumpWidget(OmniaApp(onboardingStore: store));
      expect(find.byType(OnboardingPage), findsOneWidget);
      if (exit == 'ENTER OMNIA') {
        await tester.tap(find.text('GET STARTED'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(exit));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(store.complete, isTrue);
      expect(store.writes, 1);

      // A relaunch reads the store first (see main.dart) and skips the intro.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        OmniaApp(
          onboardingStore: store,
          onboardingComplete: await store.isComplete(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(store.writes, 1);
    });
  }

  testWidgets('a restored sign-in also records the intro as done', (
    tester,
  ) async {
    phoneSize(tester, const Size(430, 932));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeAuthBackend()
      ..addUser('Sam', 'sam@example.com', 'password-123', signedIn: true);
    final api = backend.client();
    addTearDown(api.close);
    final store = MemoryOnboardingStore();
    await tester.pumpWidget(OmniaApp(api: api, onboardingStore: store));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(store.complete, isTrue);
  });

  group('SecureOnboardingStore', () {
    test('round-trips through the platform secure store', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureOnboardingStore();
      expect(await store.isComplete(), isFalse);
      await store.markComplete();
      expect(await store.isComplete(), isTrue);
      expect(await SecureOnboardingStore().isComplete(), isTrue);
    });

    test('an unreadable store shows the intro instead of failing', () async {
      final store = SecureOnboardingStore(_BrokenStorage());
      expect(await store.isComplete(), isFalse);
      await store.markComplete();
    });
  });

  testWidgets(
    'Debug preview follows the selected theme and returns to Settings',
    (tester) async {
      phoneSize(tester, const Size(430, 932));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const OmniaApp());
      await tester.tap(find.text('SKIP →'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview onboarding'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(OnboardingPage))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('SKIP →'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Onboarding is scrollable without overflow in ${brightness.name}',
      (tester) async {
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
                .descendant(
                  of: find.byType(CustomScrollView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(find.text('GET STARTED'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('GET STARTED'));
          await tester.pumpAndSettle();
          expect(find.text('How Omnia works'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('ENTER OMNIA'),
            160,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(tester.takeException(), isNull);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('SKIP →'));
          await tester.pumpAndSettle();
          expect(skipped, isTrue);
        }
      },
    );
  }
}

class _BrokenStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('keystore unavailable');

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('keystore unavailable');
}
