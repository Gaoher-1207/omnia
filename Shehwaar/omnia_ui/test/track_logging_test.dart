import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/data/api_dashboard_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/features/track/activity_log_page.dart';
import 'package:omnia_ui/features/track/data/api_track_repository.dart';
import 'package:omnia_ui/features/track/data/mock_track_repository.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';
import 'package:omnia_ui/features/track/sleep_log_page.dart';
import 'package:omnia_ui/features/track/track_controller.dart';
import 'package:omnia_ui/features/track/track_page.dart';

import 'support/fake_auth_backend.dart';

const sam = 'sam@example.com', ada = 'ada@example.com';

/// The server's today in these tests; the device clock says otherwise.
const today = '2026-09-24';
final todayDay = DateTime(2026, 9, 24);

FakeAuthBackend backend() => FakeAuthBackend()
  ..addUser('Sam', sam, 'password-123', signedIn: true)
  ..addUser('Ada', ada, 'ada-password');

Future<ApiClient> clientFor(FakeAuthBackend backend) async {
  final api = backend.client();
  addTearDown(api.close);
  await api.restoreToken();
  return api;
}

Future<ApiException> failure(Future<dynamic> call) => call.then<ApiException>(
  (_) => fail('expected an ApiException'),
  onError: (Object error) => error as ApiException,
);

/// The last activity or sleep PUT: its path and JSON body.
(String, Map<String, dynamic>) lastPut(FakeAuthBackend backend) {
  final put = backend.trackPuts.last;
  final space = put.indexOf(' ');
  return (
    put.substring(0, space),
    jsonDecode(put.substring(space + 1)) as Map<String, dynamic>,
  );
}

int dashboardLoads(FakeAuthBackend backend) =>
    backend.requests.where((r) => r == 'GET /dashboard').length;

Future<void> startApp(
  WidgetTester tester,
  FakeAuthBackend? backend, {
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (backend == null) {
    await tester.pumpWidget(const OmniaApp());
    await tester.tap(find.text('SKIP →'));
  } else {
    final api = backend.client();
    addTearDown(api.close);
    await tester.pumpWidget(OmniaApp(api: api));
  }
  await tester.pumpAndSettle();
}

/// Scrolls [page]'s list until [target] is on screen.
Future<void> reveal(WidgetTester tester, Type page, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(of: find.byType(page), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

/// Taps the card or tile called [name] on [page] (Home and Track both have
/// one of each).
Future<void> tapCard(
  WidgetTester tester,
  String name, {
  Type page = HomePage,
}) async {
  final card = find.descendant(
    of: find.byType(page),
    matching: find.text(name),
  );
  await reveal(tester, page, card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

/// Home's Settings button sits at the top of its list.
Future<void> openSettings(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byTooltip('Settings'),
    -300,
    scrollable: find
        .descendant(
          of: find.byType(HomePage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

Future<void> openTrackTab(WidgetTester tester) async {
  await tester.tap(find.text('Track').last);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> tapButton(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> pickWorkout(WidgetTester tester, String type) async {
  final menu = find.byType(DropdownButtonFormField<String?>);
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) =>
    tapButton(tester, find.widgetWithText(SolidAction, 'Save'));

/// Answers [getActivity] only when [release] is called.
class _GatedTrack implements TrackRepository {
  _GatedTrack(this._inner);
  final TrackRepository _inner;
  final gate = Completer<void>();

  @override
  Future<ActivityDay> getActivity(DateTime day) => _inner.getActivity(day);
  @override
  Future<ActivityDay> saveActivity(ActivityDay activity) async {
    await gate.future;
    return _inner.saveActivity(activity);
  }

  @override
  Future<SleepEntry?> getSleep(DateTime day) => _inner.getSleep(day);
  @override
  Future<SleepEntry> saveSleep(SleepEntry entry) => _inner.saveSleep(entry);
  @override
  Future<void> deleteSleep(DateTime day) => _inner.deleteSleep(day);
}

void main() {
  group('mapping', () {
    test('ActivityOut ↔ ActivityDay; a workout not done sends no details', () {
      final day = activityFromApi({
        'id': 'a1',
        'day': today,
        'steps': 4120,
        'workout_done': true,
        'workout_minutes': 30,
        'workout_type': 'Run',
        'updated_at': null,
      });
      expect(day.day, todayDay);
      expect(day.steps, 4120);
      expect(day.workoutDone, isTrue);
      expect(day.workoutMinutes, 30);
      expect(day.workoutType, 'Run');
      expect(activityToApi(day), {
        'steps': 4120,
        'workout_done': true,
        'workout_minutes': 30,
        'workout_type': 'Run',
      });
      final noWorkout = ActivityDay(
        day: todayDay,
        steps: 10,
        workoutMinutes: 30,
        workoutType: 'Run',
      );
      expect(activityToApi(noWorkout), {
        'steps': 10,
        'workout_done': false,
        'workout_minutes': 0,
        'workout_type': null,
      });
    });

    test('SleepOut ↔ SleepEntry; not logged is null, 0 is not', () {
      final entry = sleepFromApi({
        'day': today,
        'duration_minutes': 450,
        'quality': 4,
        'bedtime': '23:10:00',
        'wake_time': '06:40:00',
        'logged': true,
      })!;
      expect(entry.durationMinutes, 450);
      expect(entry.quality, 4);
      expect(sleepToApi(entry), {
        'duration_minutes': 450,
        'quality': 4,
        'bedtime': '23:10:00',
        'wake_time': '06:40:00',
      });
      expect(
        sleepFromApi({'day': today, 'duration_minutes': 0, 'logged': false}),
        isNull,
      );
      expect(
        sleepFromApi({'day': today, 'duration_minutes': 0, 'logged': true})!
            .durationMinutes,
        0,
      );
    });
  });

  group('ApiTrackRepository against the fake backend', () {
    test('activity: zeros when empty, whole-day PUT, stored', () async {
      final server = backend();
      final repo = ApiTrackRepository(await clientFor(server));
      final empty = await repo.getActivity(todayDay);
      expect(empty.steps, 0);
      expect(empty.workoutDone, isFalse);

      await repo.saveActivity(
        ActivityDay(
          day: todayDay,
          steps: 5000,
          workoutDone: true,
          workoutMinutes: 30,
          workoutType: 'Run',
        ),
      );
      final (path, body) = lastPut(server);
      expect(path, '/activity/$today');
      expect(body.keys, {
        'steps',
        'workout_done',
        'workout_minutes',
        'workout_type',
      });
      expect((await repo.getActivity(todayDay)).workoutType, 'Run');
    });

    test('sleep: null when empty, save, delete, then 404 on delete', () async {
      final server = backend();
      final repo = ApiTrackRepository(await clientFor(server));
      expect(await repo.getSleep(todayDay), isNull);
      await repo.saveSleep(SleepEntry(day: todayDay, durationMinutes: 0));
      expect((await repo.getSleep(todayDay))!.durationMinutes, 0);
      await repo.deleteSleep(todayDay);
      expect(await repo.getSleep(todayDay), isNull);
      expect((await failure(repo.deleteSleep(todayDay))).isNotFound, isTrue);
    });

    test("each user sees only their own day", () async {
      final server = backend()
        ..logActivity(ada, today, steps: 999)
        ..logSleep(ada, today, minutes: 300);
      final repo = ApiTrackRepository(await clientFor(server));
      expect((await repo.getActivity(todayDay)).steps, 0);
      expect(await repo.getSleep(todayDay), isNull);
    });

    test('401, future-date and range 422s, 503 and offline', () async {
      final signedOut = FakeAuthBackend()..addUser('Sam', sam, 'password-1');
      final anonymous = ApiTrackRepository(await clientFor(signedOut));
      expect(
        (await failure(anonymous.getActivity(todayDay))).isUnauthorized,
        isTrue,
      );

      final server = backend();
      final repo = ApiTrackRepository(await clientFor(server));
      final future = await failure(
        repo.saveActivity(ActivityDay(day: DateTime(2026, 9, 25))),
      );
      expect(future.statusCode, 422);
      expect(future.fieldMessage('day'), 'Date is in the future');
      final tooMany = await failure(
        repo.saveSleep(SleepEntry(day: todayDay, durationMinutes: 1441)),
      );
      expect(tooMany.fieldMessage('duration_minutes'), isNotNull);

      server.trackDown = true;
      expect((await failure(repo.getSleep(todayDay))).isUnavailable, isTrue);
      server
        ..trackDown = false
        ..offline = true;
      expect((await failure(repo.getActivity(todayDay))).isNetwork, isTrue);
    });
  });

  group('TrackController', () {
    Future<(FakeAuthBackend, TrackController, DashboardController)> setUp({
      TrackRepository Function(ApiClient api)? track,
    }) async {
      final server = backend();
      final api = await clientFor(server);
      final dashboard = DashboardController(ApiDashboardRepository(api));
      addTearDown(dashboard.dispose);
      final controller = TrackController(
        track == null ? ApiTrackRepository(api) : track(api),
        dashboard,
      );
      addTearDown(controller.dispose);
      return (server, controller, dashboard);
    }

    test('a stored change reloads the dashboard, then reports saved', () async {
      final (server, controller, dashboard) = await setUp();
      final result = await controller.saveActivity(
        ActivityDay(day: todayDay, steps: 4200),
      );
      expect(result, TrackSave.saved);
      expect(dashboardLoads(server), 1);
      expect(dashboard.dashboard!.today.steps, 4200);
    });

    test('a refused change throws and leaves the dashboard alone', () async {
      final (server, controller, _) = await setUp();
      server.trackDown = true;
      await failure(
        controller.saveSleep(SleepEntry(day: todayDay, durationMinutes: 400)),
      );
      expect(dashboardLoads(server), 0);
      expect(controller.busy, isFalse);
    });

    test('stored but not refreshed is still a save', () async {
      final (server, controller, _) = await setUp();
      server.dashboardDown = true;
      final result = await controller.saveSleep(
        SleepEntry(day: todayDay, durationMinutes: 400),
      );
      expect(result, TrackSave.savedNotRefreshed);
      expect(server.sleepOf(sam, today)!['duration_minutes'], 400);
    });

    test('deleting an entry that is already gone counts as removed', () async {
      final (_, controller, _) = await setUp();
      expect(await controller.deleteSleep(todayDay), TrackSave.saved);
    });

    test('a second change while one is in flight is ignored', () async {
      late _GatedTrack gated;
      final (server, controller, _) = await setUp(
        track: (api) => gated = _GatedTrack(ApiTrackRepository(api)),
      );
      final first = controller.saveActivity(
        ActivityDay(day: todayDay, steps: 1),
      );
      expect(controller.busy, isTrue);
      expect(
        await controller.saveActivity(ActivityDay(day: todayDay, steps: 2)),
        TrackSave.ignored,
      );
      gated.gate.complete();
      expect(await first, TrackSave.saved);
      expect(server.trackPuts, hasLength(1));
      expect(server.activityOf(sam, today)!['steps'], 1);
    });
  });

  test('mock and API dependencies share one day per mode', () async {
    final mock = AppDependencies.mock();
    expect(mock.track, isA<MockTrackRepository>());
    await mock.track.saveActivity(
      ActivityDay(day: DateTime(2025, 9, 23), steps: 7000),
    );
    expect((await mock.dashboard.getDashboard()).today.steps, 7000);

    final api = AppDependencies.api(await clientFor(backend()));
    expect(api.track, isA<ApiTrackRepository>());
  });

  group('Home and Track', () {
    testWidgets('Activity opens pre-filled; an edit keeps the workout', (
      tester,
    ) async {
      final server = backend()
        ..logActivity(
          sam,
          today,
          steps: 4120,
          workoutMinutes: 30,
          workoutType: 'Run',
        );
      await startApp(tester, server);
      expect(find.text('4,120'), findsOneWidget);

      await tapCard(tester, 'Activity');
      expect(find.byType(ActivityLogPage), findsOneWidget);
      expect(find.text('Today  ·  Thursday, September 24'), findsOneWidget);
      expect(find.text('4120'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget, reason: 'not a preset');
      expect(field('Other workout'), findsOneWidget);

      await enter(tester, 'Steps', '5000');
      await save(tester);
      final (path, body) = lastPut(server);
      expect(path, '/activity/$today', reason: "the server's day");
      expect(body, {
        'steps': 5000,
        'workout_done': true,
        'workout_minutes': 30,
        'workout_type': 'Run',
      });
      expect(find.byType(ActivityLogPage), findsNothing);
      expect(find.text('Activity saved.'), findsOneWidget);
      expect(find.text('5,000'), findsOneWidget, reason: 'Home, no restart');
    });

    testWidgets('turning the workout off clears its details, as stored', (
      tester,
    ) async {
      final server = backend()
        ..logActivity(
          sam,
          today,
          steps: 10,
          workoutMinutes: 30,
          workoutType: 'Cycling',
        );
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text('Saving without a workout clears its minutes and type.'),
        findsOneWidget,
      );
      await save(tester);
      expect(lastPut(server).$2, {
        'steps': 10,
        'workout_done': false,
        'workout_minutes': 0,
        'workout_type': null,
      });
    });

    testWidgets('a preset workout type is saved as its name', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await enter(tester, 'Workout minutes', '45');
      await pickWorkout(tester, 'Running');
      expect(field('Other workout'), findsNothing);
      await save(tester);
      expect(lastPut(server).$2['workout_type'], 'Running');

      await tapCard(tester, 'Activity');
      expect(find.text('Running'), findsOneWidget, reason: 'the preset');
      expect(field('Other workout'), findsNothing);
      await enter(tester, 'Steps', '99');
      await save(tester);
      expect(lastPut(server).$2, {
        'steps': 99,
        'workout_done': true,
        'workout_minutes': 45,
        'workout_type': 'Running',
      });
    });

    testWidgets('Other asks for the workout and saves that text', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await pickWorkout(tester, 'Other');
      await save(tester);
      expect(find.text('Describe the workout'), findsOneWidget);
      expect(server.trackPuts, isEmpty);

      await enter(tester, 'Other workout', '  Climbing ');
      await save(tester);
      expect(lastPut(server).$2['workout_type'], 'Climbing');
    });

    testWidgets('no type chosen saves none', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Not specified'), findsOneWidget);
      await save(tester);
      expect(lastPut(server).$2['workout_type'], isNull);
    });

    testWidgets('a custom type survives switching to a preset and back', (
      tester,
    ) async {
      final server = backend()
        ..logActivity(
          sam,
          today,
          steps: 10,
          workoutMinutes: 20,
          workoutType: 'Kayaking at dawn',
        );
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      expect(find.text('Kayaking at dawn'), findsOneWidget);
      await pickWorkout(tester, 'Walking');
      await pickWorkout(tester, 'Other');
      await save(tester);
      expect(
        server.activityOf(sam, today)!['workout_type'],
        'Kayaking at dawn',
      );
    });

    testWidgets('Sleep opens pre-filled; an edit keeps bedtime and wake time', (
      tester,
    ) async {
      final server = backend()
        ..logSleep(
          sam,
          today,
          minutes: 450,
          quality: 4,
          bedtime: '23:10:00',
          wakeTime: '06:40:00',
        );
      await startApp(tester, server);
      expect(find.text('7h 30m'), findsOneWidget);

      await tapCard(tester, 'Sleep');
      expect(find.byType(SleepLogPage), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('4 · Good'), findsOneWidget);
      expect(
        find.text(
          'Your logged bedtime 23:10 and wake time 06:40 stay as they are.',
        ),
        findsOneWidget,
      );

      await enter(tester, 'Hours', '8');
      await enter(tester, 'Minutes', '15');
      await save(tester);
      final (path, body) = lastPut(server);
      expect(path, '/sleep/$today');
      expect(body, {
        'duration_minutes': 495,
        'quality': 4,
        'bedtime': '23:10:00',
        'wake_time': '06:40:00',
      });
      expect(find.text('8h 15m'), findsOneWidget);
    });

    testWidgets('no entry: a clean form; logging it shows on Home', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      expect(find.text('Not logged'), findsOneWidget);
      await tapCard(tester, 'Sleep');
      expect(find.textContaining('not logged yet'), findsOneWidget);
      expect(find.text('Remove entry'), findsNothing);
      await enter(tester, 'Hours', '6');
      await save(tester);
      expect(lastPut(server).$2, {
        'duration_minutes': 360,
        'quality': null,
        'bedtime': null,
        'wake_time': null,
      });
      expect(find.text('6h'), findsOneWidget);
      expect(find.text('Not logged'), findsNothing);
    });

    testWidgets('removing sleep asks first, then Home shows Not logged', (
      tester,
    ) async {
      final server = backend()..logSleep(sam, today, minutes: 450);
      await startApp(tester, server);
      await tapCard(tester, 'Sleep');
      await tapButton(tester, find.text('Remove entry'));
      expect(find.text('Remove this sleep entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(server.sleepOf(sam, today), isNull);
      expect(find.text('Sleep entry removed.'), findsOneWidget);
      expect(find.text('Not logged'), findsOneWidget);
    });

    testWidgets('Track tiles open the log screens and Tasks', (tester) async {
      await startApp(tester, backend());
      await openTrackTab(tester);
      expect(find.byType(TrackPage), findsOneWidget);
      await tapCard(tester, 'Activity', page: TrackPage);
      expect(find.byType(ActivityLogPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapCard(tester, 'Sleep', page: TrackPage);
      expect(find.byType(SleepLogPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapCard(tester, 'Tasks', page: TrackPage);
      expect(find.byType(TasksPage), findsOneWidget);
    });

    testWidgets('Home Tasks card opens Tasks; Study still opens Track', (
      tester,
    ) async {
      await startApp(tester, backend());
      await tapCard(tester, 'Tasks');
      expect(find.byType(TasksPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tapCard(tester, 'Study');
      expect(find.byType(TrackPage).hitTestable(), findsOneWidget);
    });

    testWidgets('before today has loaded there is nothing to log against', (
      tester,
    ) async {
      final server = backend()..dashboardDown = true;
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      expect(find.byType(ActivityLogPage), findsNothing);
      expect(find.text(notLoadedMessage), findsOneWidget);
      expect(server.trackPuts, isEmpty);
    });

    testWidgets('out-of-range values are explained before sending', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await enter(tester, 'Steps', '300000');
      await save(tester);
      expect(find.text('Enter a number from 0 to 200,000'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tapCard(tester, 'Sleep');
      await save(tester);
      expect(find.text('Enter how long you slept'), findsOneWidget);
      await enter(tester, 'Hours', '7');
      await enter(tester, 'Minutes', '75');
      await save(tester);
      expect(find.text('Enter 0 to 59'), findsOneWidget);
      expect(server.trackPuts, isEmpty);
    });

    testWidgets('offline: an error, and the typed values stay', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await enter(tester, 'Steps', '4321');
      server.offline = true;
      await save(tester);
      expect(find.byType(ActivityLogPage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('4321'), findsOneWidget);
    });

    testWidgets('saved but Home could not refresh says so', (tester) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Sleep');
      await enter(tester, 'Hours', '7');
      server.dashboardDown = true;
      await save(tester);
      expect(find.byType(SleepLogPage), findsNothing, reason: 'it saved');
      expect(find.textContaining("Home couldn't refresh"), findsOneWidget);
      expect(server.sleepOf(sam, today)!['duration_minutes'], 420);
    });

    testWidgets('an expired session while saving returns to sign-in', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await enter(tester, 'Steps', '4321');
      server.endSessions(sam);
      await save(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(server.activityOf(sam, today), isNull);
    });

    testWidgets("the next user never sees the last user's day", (tester) async {
      final server = backend()..logSleep(ada, today, minutes: 300);
      await startApp(tester, server);
      await tapCard(tester, 'Activity');
      await enter(tester, 'Steps', '4321');
      await save(tester);
      expect(find.text('4,321'), findsOneWidget);

      await openSettings(tester);
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

      expect(find.text('4,321'), findsNothing);
      expect(find.text('5h'), findsOneWidget, reason: "Ada's own sleep");
      await tapCard(tester, 'Activity');
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('mock mode: logging changes the mock Home at once', (
      tester,
    ) async {
      await startApp(tester, null);
      expect(find.text('6,240'), findsOneWidget);
      await tapCard(tester, 'Activity');
      expect(find.text('6240'), findsOneWidget);
      await enter(tester, 'Steps', '7000');
      await save(tester);
      expect(find.text('7,000'), findsOneWidget);

      await tapCard(tester, 'Sleep');
      await tapButton(tester, find.text('Remove entry'));
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Not logged'), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets(
        'log screens fit 200% text on a 360px phone (${dark ? 'dark' : 'light'})',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final server = backend()
            ..logActivity(
              sam,
              today,
              steps: 4120,
              workoutMinutes: 30,
              workoutType: 'Run',
            )
            ..logSleep(
              sam,
              today,
              minutes: 450,
              quality: 4,
              bedtime: '23:10:00',
              wakeTime: '06:40:00',
            );
          await startApp(tester, server, size: const Size(360, 800));
          if (dark) {
            await openSettings(tester);
            await tester.scrollUntilVisible(
              find.text('Dark'),
              200,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.tap(find.text('Dark'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Back'));
            await tester.pumpAndSettle();
          }
          for (final name in ['Activity', 'Sleep']) {
            await tapCard(tester, name);
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 8; i++) {
              await tester.drag(
                find.byType(ListView).last,
                const Offset(0, -300),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            expect(find.widgetWithText(SolidAction, 'Save'), findsOneWidget);
            await tester.tap(find.byTooltip('Back'));
            await tester.pumpAndSettle();
          }
        },
      );
    }
  });
}
