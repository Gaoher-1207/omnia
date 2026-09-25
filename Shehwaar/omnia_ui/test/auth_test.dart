import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/goals/goal_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';

import 'support/fake_auth_backend.dart';

const email = 'sam@example.com', password = 'password-123';

/// Starts the app in API mode against [backend]; returns its client.
Future<ApiClient> startApiApp(
  WidgetTester tester,
  FakeAuthBackend backend,
) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
  return api;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> tapAction(WidgetTester tester, String label) async {
  final button = find.widgetWithText(SolidAction, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> skipOnboarding(WidgetTester tester) async {
  await tester.tap(find.text('SKIP →'));
  await tester.pumpAndSettle();
}

/// From the sign-up form (the default), switch to sign-in and submit.
Future<void> signIn(
  WidgetTester tester, {
  String as = email,
  String with_ = password,
}) async {
  if (find.text('Already have an account? Sign in').evaluate().isNotEmpty) {
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(field('Email'), as);
  await tester.enterText(field('Password'), with_);
  await tapAction(tester, 'Sign in');
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> tapTile(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.widgetWithText(ListTile, title));
  await tester.tap(find.widgetWithText(ListTile, title));
  await tester.pumpAndSettle();
}

TaskController tasksOf(WidgetTester tester) =>
    TaskScope.of(tester.element(find.byType(HomePage)));

void main() {
  testWidgets('mock mode needs no sign-in and shows no account controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const OmniaApp());
    await skipOnboarding(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(AuthPage), findsNothing);
    await openSettings(tester);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('API mode restores a stored session straight into the app', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    await startApiApp(tester, backend);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    // The session loads this user's data only after the account is known.
    expect(backend.requests, ['GET /auth/me', 'GET /dashboard', 'GET /tasks']);

    await openSettings(tester);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text(email), findsOneWidget);
  });

  testWidgets('without a token: onboarding, then sign-in', (tester) async {
    final backend = FakeAuthBackend()..addUser('Sam', email, password);
    await startApiApp(tester, backend);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(backend.requests, isEmpty, reason: 'no token, nothing to check');
    await skipOnboarding(tester);
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);

    await signIn(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(backend.tokens.token, isNotNull);
    expect(backend.isValid(backend.tokens.token!), isTrue);
  });

  testWidgets('a rejected stored token falls back to sign-in', (tester) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    backend.endSessions(email);
    await startApiApp(tester, backend);
    await skipOnboarding(tester);
    expect(find.byType(AuthPage), findsOneWidget);
    expect(backend.tokens.token, isNull);
  });

  testWidgets('offline at launch keeps the session and offers a retry', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true)
      ..offline = true;
    await startApiApp(tester, backend);
    expect(find.text("Couldn't reach OMNIA"), findsOneWidget);
    expect(backend.tokens.token, isNotNull);

    backend.offline = false;
    await tapAction(tester, 'Try again');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('invalid credentials explain themselves and stay on sign-in', (
    tester,
  ) async {
    final backend = FakeAuthBackend()..addUser('Sam', email, password);
    await startApiApp(tester, backend);
    await skipOnboarding(tester);
    await signIn(tester, with_: 'wrong-password');
    expect(find.text('Incorrect email or password'), findsOneWidget);
    expect(find.byType(AuthPage), findsOneWidget);
    expect(backend.tokens.token, isNull);
  });

  testWidgets('registration validates, shows backend errors, then signs in', (
    tester,
  ) async {
    final backend = FakeAuthBackend()..addUser('Sam', email, password);
    await startApiApp(tester, backend);
    await skipOnboarding(tester);

    await tapAction(tester, 'Create account');
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(backend.requests, isEmpty, reason: 'checked before sending');

    await tester.enterText(field('What should we call you?'), 'Ada');
    await tester.enterText(field('Email'), 'ada@nowhere');
    await tester.enterText(field('Password'), 'short');
    await tapAction(tester, 'Create account');
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    // Passes the app's checks; the backend rejects it, shown on the field.
    await tester.enterText(field('Password'), 'long-enough-1');
    await tapAction(tester, 'Create account');
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.enterText(field('Email'), email);
    await tapAction(tester, 'Create account');
    expect(
      find.text('An account with this email already exists'),
      findsOneWidget,
    );

    await tester.enterText(field('Email'), 'ada@example.com');
    await tapAction(tester, 'Create account');
    expect(find.byType(HomePage), findsOneWidget);
    expect(backend.hasUser('ada@example.com'), isTrue);
    expect(backend.timezoneOf('ada@example.com'), isNotEmpty);
  });

  testWidgets('sign out returns to sign-in, not onboarding', (tester) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    await startApiApp(tester, backend);
    await openSettings(tester);
    await tapTile(tester, 'Sign out');
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(backend.tokens.token, isNull);
  });

  testWidgets('sign out everywhere confirms, then revokes every token', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    final token = backend.tokens.token!;
    await startApiApp(tester, backend);
    await openSettings(tester);

    await tapTile(tester, 'Sign out everywhere');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.isValid(token), isTrue);

    await tapTile(tester, 'Sign out everywhere');
    await tester.tap(find.widgetWithText(TextButton, 'Sign out everywhere'));
    await tester.pumpAndSettle();
    expect(backend.isValid(token), isFalse);
    expect(backend.tokens.token, isNull);
    expect(find.byType(AuthPage), findsOneWidget);
  });

  testWidgets('change password: wrong current password, then success', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    final oldToken = backend.tokens.token!;
    await startApiApp(tester, backend);
    await openSettings(tester);

    await tapTile(tester, 'Change password');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your current password'), findsOneWidget);
    await tester.enterText(field('Current password'), 'not-it');
    await tester.enterText(field('New password'), 'brand-new-pass');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    // A wrong password (403) must not look like an expired session.
    expect(find.text('Current password is incorrect'), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);

    await tapTile(tester, 'Change password');
    await tester.enterText(field('Current password'), password);
    await tester.enterText(field('New password'), 'brand-new-pass');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Password changed'), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget, reason: 'still in');
    expect(backend.passwordOf(email), 'brand-new-pass');
    expect(backend.isValid(oldToken), isFalse);
    expect(backend.isValid(backend.tokens.token!), isTrue);
  });

  testWidgets('delete account: wrong password, then deleted and signed out', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    await startApiApp(tester, backend);
    await openSettings(tester);

    await tapTile(tester, 'Delete account');
    await tester.enterText(field('Confirm with your password'), 'nope');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(find.text('Password is incorrect'), findsOneWidget);
    expect(backend.hasUser(email), isTrue);

    await tapTile(tester, 'Delete account');
    await tester.enterText(field('Confirm with your password'), password);
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(backend.hasUser(email), isFalse);
    expect(find.byType(AuthPage), findsOneWidget);
  });

  testWidgets('an expired session returns to sign-in once, with a notice', (
    tester,
  ) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true);
    final api = await startApiApp(tester, backend);
    await openSettings(tester);
    backend.endSessions(email);

    var expiries = 0;
    api.onUnauthorized.listen((_) => expiries++);
    // Two requests in flight when the session dies: both are rejected.
    final first = api.get('/profile').catchError((_) => null);
    final second = api.get('/dashboard').catchError((_) => null);
    await tester.pumpAndSettle();
    await first;
    await second;

    expect(expiries, 2);
    expect(find.byType(SettingsPage), findsNothing, reason: 'screens closed');
    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('Your session ended. Please sign in again.'),
      findsOneWidget,
    );
    expect(backend.tokens.token, isNull);

    // Signed out now: a later rejection is not another expiry.
    await api.get('/profile').catchError((_) => null);
    await tester.pumpAndSettle();
    expect(expiries, 2);
    expect(find.byType(AuthPage), findsOneWidget);
  });

  testWidgets('each signed-in user gets fresh session state', (tester) async {
    final backend = FakeAuthBackend()
      ..addUser('Sam', email, password, signedIn: true)
      ..addUser('Ada', 'ada@example.com', 'ada-password');
    backend
      ..addTask(email, 'Sam task')
      ..addTask('ada@example.com', 'Ada task');
    await startApiApp(tester, backend);

    final samTasks = tasksOf(tester);
    final samGoals = GoalScope.of(tester.element(find.byType(HomePage)));
    expect(samTasks.tasks.map((t) => t.title), ['Sam task']);
    await samTasks.setCompleted(samTasks.tasks.first.id, true);
    await tester.pumpAndSettle();
    expect(samTasks.completedCount, 1);

    await openSettings(tester);
    await tapTile(tester, 'Sign out');
    await signIn(tester, as: 'ada@example.com', with_: 'ada-password');

    final adaTasks = tasksOf(tester);
    expect(identical(adaTasks, samTasks), isFalse);
    expect(
      identical(GoalScope.of(tester.element(find.byType(HomePage))), samGoals),
      isFalse,
    );
    expect(adaTasks.tasks.map((t) => t.title), ['Ada task']);
    expect(adaTasks.completedCount, 0, reason: "Sam's changes don't leak");
  });

  group('AuthPage layout', () {
    for (final brightness in Brightness.values) {
      testWidgets('fits 200% text in ${brightness.name} mode', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // Tall enough to lay out every field; overflow here is horizontal.
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final backend = FakeAuthBackend();
        final api = backend.client();
        addTearDown(api.close);
        final auth = AuthController(api);
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: AuthScope(controller: auth, child: const AuthPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Time zone'), findsOneWidget);

        await tapAction(tester, 'Create account');
        expect(find.text('Enter your name'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Already have an account? Sign in'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text('Time zone'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('announces its heading and switches modes', (tester) async {
      final semantics = tester.ensureSemantics();
      final api = FakeAuthBackend().client();
      addTearDown(api.close);
      final auth = AuthController(api);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AuthScope(controller: auth, child: const AuthPage()),
        ),
      );
      expect(
        tester.getSemantics(find.text('Create your account')),
        isSemantics(label: 'Create your account', isHeader: true),
      );
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      semantics.dispose();
    });
  });
}
