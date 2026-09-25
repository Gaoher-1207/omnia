import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/home/domain/dashboard_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/settings/profile_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

FakeAuthBackend backend() => FakeAuthBackend()
  ..addUser('Sam', sam, 'password-123', signedIn: true)
  ..addUser('Ada', ada, 'ada-password');

Map<String, dynamic> profileJson({
  String name = 'Sam',
  String timezone = 'UTC',
  String? username,
  int study = 240,
}) => {
  'display_name': name,
  'timezone': timezone,
  'username': username,
  'daily_study_goal_minutes': study,
  'daily_step_goal': 8000,
  'daily_task_goal': 5,
  'preferred_workout_time': 'evening',
  'daily_sleep_goal_minutes': 480,
  'daily_calorie_goal': 2000,
};

Future<AuthController> signedInAuth(FakeAuthBackend backend) async {
  final api = backend.client();
  addTearDown(api.close);
  final auth = AuthController(api);
  addTearDown(auth.dispose);
  await auth.restore();
  return auth;
}

Future<ApiException> failure(Future<dynamic> call) => call.then<ApiException>(
  (_) => fail('expected an ApiException'),
  onError: (Object error) => error as ApiException,
);

Future<void> startApp(
  WidgetTester tester,
  FakeAuthBackend backend, {
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = backend.client();
  addTearDown(api.close);
  await tester.pumpWidget(OmniaApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> openProfile(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Profile & daily targets'));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

/// Scrolls the editor until [target] is built and on screen.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ProfilePage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await reveal(tester, field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(SolidAction, 'Save');
  await reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// From the editor (or Settings) back to Home.
Future<void> backToHome(WidgetTester tester) async {
  while (find.byType(HomePage).hitTestable().evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  }
}

/// A dashboard whose first request waits until [release] is called.
class _SlowDashboards implements DashboardRepository {
  final gate = Completer<void>();
  var calls = 0;
  void release() => gate.complete();

  @override
  Future<Dashboard> getDashboard() async {
    final call = ++calls;
    if (call == 1) await gate.future;
    return Dashboard(
      date: DateTime(2026, 9, 24),
      greeting: 'morning',
      displayName: 'call $call',
      today: const TodaySummary(
        studyMinutes: 0,
        studyGoalMinutes: 240,
        steps: 0,
        stepGoal: 8000,
        sleepGoalMinutes: 480,
      ),
    );
  }
}

void main() {
  group('Profile model', () {
    test('ProfileOut → Profile, and User keeps its id and email', () {
      final user = User.fromJson({
        'id': 'u1',
        'email': sam,
        'created_at': '2026-09-24T08:00:00Z',
        'profile': profileJson(username: 'sam_k'),
      });
      expect(user.displayName, 'Sam');
      expect(user.username, 'sam_k');
      expect(user.profile.studyGoalMinutes, 240);
      expect(user.profile.stepGoal, 8000);
      expect(user.profile.taskGoal, 5);
      expect(user.profile.sleepGoalMinutes, 480);
      expect(user.profile.calorieGoal, 2000);
      expect(user.profile.workoutTime, WorkoutTime.evening);

      final renamed = user.withProfile(
        Profile.fromJson(profileJson(name: 'Samuel')),
      );
      expect(renamed.id, 'u1');
      expect(renamed.email, sam);
      expect(renamed.displayName, 'Samuel');
    });

    test('changesSince lists only the fields that differ', () {
      final before = Profile.fromJson(profileJson(username: 'sam_k'));
      expect(before.changesSince(before), isEmpty);
      final after = Profile.fromJson(
        profileJson(study: 180, timezone: 'Asia/Tokyo'),
      );
      expect(after.changesSince(before), {
        'daily_study_goal_minutes': 180,
        'timezone': 'Asia/Tokyo',
        'username': null, // cleared, so sent as an explicit null
      });
    });
  });

  group('AuthController.updateProfile', () {
    test('PATCHes the changes and keeps the returned profile', () async {
      final server = backend();
      final auth = await signedInAuth(server);
      final id = auth.user!.id;
      await auth.updateProfile({'daily_step_goal': 10000, 'username': 'Sam_K'});
      expect(server.profilePatches, [
        {'daily_step_goal': 10000, 'username': 'Sam_K'},
      ]);
      expect(auth.user!.profile.stepGoal, 10000);
      expect(auth.user!.username, 'sam_k', reason: 'as the server stored it');
      expect(auth.user!.id, id);
      expect(auth.status, AuthStatus.signedIn);
    });

    test('nothing changed, nothing sent', () async {
      final server = backend();
      final auth = await signedInAuth(server);
      await auth.updateProfile({});
      expect(server.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    });

    test(
      'a taken username or bad value is refused; profile unchanged',
      () async {
        final server = backend();
        server.profileOf(ada)!['username'] = 'ada';
        final auth = await signedInAuth(server);

        final taken = await failure(auth.updateProfile({'username': 'ada'}));
        expect(taken.statusCode, 409);
        expect(taken.message, 'That username is taken');

        final tooHigh = await failure(
          auth.updateProfile({'daily_task_goal': 51}),
        );
        expect(tooHigh.fieldMessage('daily_task_goal'), isNotNull);
        expect(auth.user!.username, isNull);
        expect(auth.user!.profile.taskGoal, 5);
      },
    );
  });

  test('a load asked for mid-flight fetches again afterwards', () async {
    final repository = _SlowDashboards();
    final controller = DashboardController(repository);
    addTearDown(controller.dispose);
    final first = controller.load();
    final second = controller.load(); // e.g. after a save
    expect(identical(first, second), isTrue);
    repository.release();
    await second;
    expect(repository.calls, 2);
    expect(controller.dashboard!.displayName, 'call 2');
    expect(controller.loading, isFalse);
  });

  group('Profile & daily targets screen', () {
    testWidgets('mock mode has no profile editor', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const OmniaApp());
      await tester.tap(find.text('SKIP →'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Profile & daily targets'), findsNothing);
    });

    testWidgets('a new study target shows on Home and Track at once', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      expect(find.text('/ 4h'), findsOneWidget);

      await openProfile(tester);
      await enter(tester, 'Study (minutes a day)', '180');
      expect(find.text('= 3h'), findsOneWidget, reason: 'live helper');
      await save(tester);

      expect(server.profilePatches, [
        {'daily_study_goal_minutes': 180},
      ]);
      expect(find.byType(ProfilePage), findsNothing);
      expect(find.text('Profile saved.'), findsOneWidget);
      await backToHome(tester);
      expect(find.text('/ 3h'), findsOneWidget);
      expect(find.text('/ 4h'), findsNothing);
      await tester.tap(find.text('Track').last);
      await tester.pumpAndSettle();
      expect(find.text('3h goal'), findsOneWidget);
    });

    testWidgets('a new name updates the greeting and Settings', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Name', '  Samuel ');
      await save(tester);
      expect(server.profilePatches.single, {'display_name': 'Samuel'});
      expect(find.text('Samuel'), findsOneWidget, reason: 'Settings card');
      await backToHome(tester);
      expect(find.text('Good morning,\nSamuel.'), findsOneWidget);
    });

    testWidgets("a new time zone moves Home to that zone's day", (
      tester,
    ) async {
      final server = backend()..dateInZone['Pacific/Auckland'] = '2026-09-25';
      await startApp(tester, server);
      expect(find.text('Thursday, September 24'), findsOneWidget);
      await openProfile(tester);
      await tester.tap(find.text('UTC'));
      await tester.pumpAndSettle();
      // Only the open menu lists it.
      await tester.scrollUntilVisible(
        find.text('Pacific/Auckland'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Pacific/Auckland'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(server.profilePatches.single, {'timezone': 'Pacific/Auckland'});
      await backToHome(tester);
      expect(find.text('Friday, September 25'), findsOneWidget);
    });

    testWidgets('a taken username is shown on the username field', (
      tester,
    ) async {
      final server = backend();
      server.profileOf(ada)!['username'] = 'ada';
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Username (optional)', 'Ada');
      await save(tester);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Check the highlighted fields.'), findsOneWidget);
      await reveal(tester, field('Username (optional)'));
      expect(find.text('That username is taken'), findsOneWidget);
      expect(server.profileOf(sam)!['username'], isNull);
    });

    testWidgets('out-of-range values are caught before sending', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Sleep (minutes a night)', '1000');
      await enter(tester, 'Username (optional)', 'x');
      await save(tester);
      expect(find.text('Check the highlighted fields.'), findsOneWidget);
      await reveal(tester, find.text('Enter a number from 0 to 960'));
      await reveal(tester, find.text('Use 3–30 letters, digits or _'));
      expect(server.profilePatches, isEmpty);
    });

    testWidgets('saving with no changes sends nothing', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await save(tester);
      expect(find.byType(ProfilePage), findsNothing);
      expect(server.profilePatches, isEmpty);
    });

    testWidgets('a save that stood but Home could not refresh says so', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Steps a day', '10000');
      server.dashboardDown = true;
      await save(tester);
      expect(find.byType(ProfilePage), findsNothing, reason: 'it saved');
      expect(find.textContaining("Home couldn't refresh"), findsOneWidget);
      expect(server.profileOf(sam)!['daily_step_goal'], 10000);
    });

    testWidgets('offline: an error, and the form keeps its input', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Steps a day', '10000');
      server.offline = true;
      await save(tester);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('10000'), findsOneWidget);
    });

    testWidgets('an expired session while saving returns to sign-in', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Steps a day', '10000');
      server.endSessions(sam);
      await save(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(
        find.text('Your session ended. Please sign in again.'),
        findsOneWidget,
      );
      expect(server.profileOf(sam)!['daily_step_goal'], 8000);
    });

    testWidgets("the next user sees their own targets, not the last user's", (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openProfile(tester);
      await enter(tester, 'Study (minutes a day)', '120');
      await save(tester);

      final signOut = find.widgetWithText(ListTile, 'Sign out');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email'), ada);
      await tester.enterText(field('Password'), 'ada-password');
      await tester.tap(find.widgetWithText(SolidAction, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('/ 4h'), findsOneWidget);
      expect(find.text('/ 2h'), findsNothing);
      await openProfile(tester);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('240'), findsOneWidget);
      expect(server.profileOf(ada)!['daily_study_goal_minutes'], 240);
    });

    testWidgets('fits 200% text on a 360px phone', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await startApp(tester, backend(), size: const Size(360, 800));
      await openProfile(tester);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 20; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.widgetWithText(SolidAction, 'Save'), findsOneWidget);
    });
  });
}
