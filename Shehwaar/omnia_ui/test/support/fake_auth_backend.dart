import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/auth/timezones.dart';
import 'package:omnia_ui/core/auth/token_store.dart';

/// An in-memory stand-in for the backend's auth, profile, tasks and dashboard
/// endpoints, speaking the same JSON and status codes as
/// `Fawaz/backend/app/modules/{auth,users,tasks,dashboard}`.
class FakeAuthBackend {
  /// The device's token storage, shared with every [client].
  final tokens = MemoryTokenStore();
  final requests = <String>[];
  bool offline = false;

  /// Makes every `/tasks` call answer 503, like a failing server.
  bool tasksDown = false;

  /// Makes `GET /dashboard` answer 503.
  bool dashboardDown = false;

  /// The server's "today" (in the profile timezone), independent of the
  /// device clock.
  String dashboardDate = '2026-09-24';

  /// "Today" for users in other time zones, e.g. `{'Pacific/Auckland':
  /// '2026-09-25'}`; everyone else gets [dashboardDate].
  final dateInZone = <String, String>{};

  /// Every `PATCH /profile` body, in order.
  final profilePatches = <Map<String, dynamic>>[];

  final _users = <String, Map<String, dynamic>>{}; // email → account
  final _sessions = <String, String>{}; // token → email
  final _tasks = <String, Map<String, dynamic>>{}; // id → task + owner
  final _today = <String, Map<String, dynamic>>{}; // email → logged totals
  final _nextExam = <String, Map<String, dynamic>>{}; // email → exam
  var _ids = 0;

  /// Stores a task for [email] as the server would; returns its id.
  String addTask(String email, String title, {bool done = false}) {
    final task = _newTask(email, {'title': title});
    if (done) task['status'] = 'done';
    return task['id'] as String;
  }

  /// Today's logged totals for [email], e.g. `{'steps': 4120}`.
  void setToday(String email, Map<String, dynamic> values) =>
      (_today[email] ??= {}).addAll(values);

  /// [email]'s nearest upcoming exam, or none.
  void setNextExam(
    String email, {
    required String subject,
    required String title,
    required String date,
    required int daysLeft,
  }) => _nextExam[email] = {
    'id': 'exam-uuid-${++_ids}',
    'title': title,
    'subject_name': subject,
    'exam_date': date,
    'days_left': daysLeft,
  };

  /// [email]'s tasks as the API returns them.
  List<Map<String, dynamic>> tasksOf(String email) => [
    for (final task in _tasks.values)
      if (task['owner'] == email) _taskOut(task),
  ];

  /// Adds an account. With [signedIn], this device already holds its token.
  void addUser(
    String name,
    String email,
    String password, {
    bool signedIn = false,
  }) {
    _users[email] = {
      'id': 'user-${++_ids}',
      'password': password,
      // `ProfileOut`, with the backend's defaults.
      'profile': <String, dynamic>{
        'display_name': name,
        'timezone': 'UTC',
        'username': null,
        'daily_study_goal_minutes': 240,
        'daily_step_goal': 8000,
        'daily_task_goal': 5,
        'preferred_workout_time': 'evening',
        'daily_sleep_goal_minutes': 480,
        'daily_calorie_goal': 2000,
      },
    };
    if (signedIn) tokens.token = _issue(email);
  }

  bool hasUser(String email) => _users.containsKey(email);
  String? passwordOf(String email) => _users[email]?['password'] as String?;
  bool isValid(String token) => _sessions.containsKey(token);
  String? timezoneOf(String email) => profileOf(email)?['timezone'] as String?;

  /// [email]'s stored `ProfileOut`.
  Map<String, dynamic>? profileOf(String email) =>
      _users[email]?['profile'] as Map<String, dynamic>?;

  /// Server-side revocation, e.g. the token expired.
  void endSessions(String email) =>
      _sessions.removeWhere((_, owner) => owner == email);

  ApiClient client() => ApiClient(
    baseUrl: 'http://omnia.test/api',
    tokens: tokens,
    httpClient: MockClient(_handle),
  );

  String _issue(String email) {
    final token = 'token-${++_ids}';
    _sessions[token] = email;
    return token;
  }

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api', '');
    requests.add('${request.method} $path');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    switch ((request.method, path)) {
      case ('POST', '/auth/register'):
        final email = '${body['email']}'.trim().toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          return _invalid('body.email', 'Enter a valid email address');
        }
        if ('${body['password']}'.length < 8) {
          return _invalid(
            'body.password',
            'String should have at least 8 characters',
          );
        }
        if (hasUser(email)) {
          return _error(
            409,
            'conflict',
            'An account with this email already exists',
          );
        }
        addUser('${body['display_name']}', email, '${body['password']}');
        profileOf(email)!['timezone'] = '${body['timezone']}';
        return _json(_tokenResponse(email), 201);
      case ('POST', '/auth/login'):
        final email = '${body['email']}'.trim().toLowerCase();
        if (passwordOf(email) != body['password']) {
          return _error(401, 'unauthorized', 'Incorrect email or password');
        }
        return _json(_tokenResponse(email));
    }

    final token = (request.headers['Authorization'] ?? '').replaceFirst(
      'Bearer ',
      '',
    );
    final email = _sessions[token];
    if (email == null) {
      return _error(
        401,
        'unauthorized',
        'Your session has expired or is invalid. Please sign in again.',
      );
    }
    switch ((request.method, path)) {
      case ('GET', '/auth/me'):
        return _json(_user(email));
      case ('POST', '/auth/logout-all'):
        endSessions(email);
        return http.Response('', 204);
      case ('POST', '/auth/change-password'):
        if (body['current_password'] != passwordOf(email)) {
          return _error(403, 'forbidden', 'Current password is incorrect');
        }
        if ('${body['new_password']}'.length < 8) {
          return _invalid(
            'body.new_password',
            'String should have at least 8 characters',
          );
        }
        _users[email]!['password'] = '${body['new_password']}';
        endSessions(email);
        return _json(_tokenResponse(email));
      case ('POST', '/auth/delete-account'):
        if (body['password'] != passwordOf(email)) {
          return _error(403, 'forbidden', 'Password is incorrect');
        }
        endSessions(email);
        _users.remove(email);
        _tasks.removeWhere((_, task) => task['owner'] == email); // cascade
        _today.remove(email);
        _nextExam.remove(email);
        return http.Response('', 204);
      case ('GET', '/profile'):
        return _json(profileOf(email)!);
      case ('PATCH', '/profile'):
        profilePatches.add(body);
        return _patchProfile(email, body);
      case ('GET', '/dashboard'):
        if (dashboardDown) {
          return _error(503, 'service_unavailable', 'Dashboard unavailable.');
        }
        return _json(_dashboard(email));
    }
    if (path == '/tasks' || path.startsWith('/tasks/')) {
      return _handleTasks(request.method, path, request.url, body, email);
    }
    // Any other signed-in request (features not on the backend yet).
    return _json(<String, dynamic>{});
  }

  static const _taskFields = {
    'title',
    'notes',
    'priority',
    'due_date',
    'due_time',
    'estimated_minutes',
    'category',
  };

  http.Response _handleTasks(
    String method,
    String path,
    Uri url,
    Map<String, dynamic> body,
    String email,
  ) {
    if (tasksDown) {
      return _error(503, 'service_unavailable', 'Tasks are unavailable.');
    }
    if (path == '/tasks') {
      if (method == 'GET') {
        final mine = tasksOf(email);
        final limit = int.parse(url.queryParameters['limit'] ?? '50');
        final offset = int.parse(url.queryParameters['offset'] ?? '0');
        if (limit > 200) return _invalid('query.limit', 'at most 200');
        return _json({
          'items': mine.skip(offset).take(limit).toList(),
          'total': mine.length,
          'limit': limit,
          'offset': offset,
        });
      }
      final problem = _checkTask(body, patch: false);
      if (problem != null) return problem;
      return _json(_taskOut(_newTask(email, body)), 201);
    }

    // Someone else's task is "not found", as on the real backend.
    final task = _tasks[path.substring('/tasks/'.length)];
    if (task == null || task['owner'] != email) {
      return _error(404, 'not_found', 'Task not found');
    }
    switch (method) {
      case 'GET':
        return _json(_taskOut(task));
      case 'DELETE':
        _tasks.remove(task['id']);
        return http.Response('', 204);
      case 'PATCH':
        final problem = _checkTask(body, patch: true);
        if (problem != null) return problem;
        if (body['status'] == 'done' && task['status'] != 'done') {
          task['completed_at'] = _now();
        } else if (body['status'] == 'todo') {
          task['completed_at'] = null;
        }
        task.addAll(_normalized(body));
        if (task['due_date'] == null) task['due_time'] = null;
        task['updated_at'] = _now();
        return _json(_taskOut(task));
    }
    return _error(405, 'method_not_allowed', 'Method not allowed');
  }

  /// The backend's request rules (`TaskCreate` / `TaskUpdate`).
  http.Response? _checkTask(Map<String, dynamic> body, {required bool patch}) {
    for (final field in body.keys) {
      if (!_taskFields.contains(field) && !(patch && field == 'status')) {
        return _invalid('body.$field', 'Extra inputs are not permitted');
      }
    }
    for (final field in ['title', 'priority', 'status', 'category']) {
      if (body.containsKey(field) && body[field] == null) {
        return _invalid('body', 'These fields cannot be null: $field');
      }
    }
    final title = body['title'] as String?;
    if ((!patch || title != null) && (title ?? '').trim().isEmpty) {
      return _invalid('body.title', 'String should have at least 1 character');
    }
    final minutes = body['estimated_minutes'] as int?;
    if (minutes != null && (minutes < 1 || minutes > 1440)) {
      return _invalid('body.estimated_minutes', 'Must be 1 to 1440');
    }
    if (!patch && body['due_time'] != null && body['due_date'] == null) {
      return _invalid('body', 'due_time needs a due_date');
    }
    return null;
  }

  Map<String, dynamic> _newTask(String email, Map<String, dynamic> body) {
    final id = 'task-uuid-${++_ids}';
    final now = _now();
    return _tasks[id] = {
      'id': id,
      'owner': email,
      'notes': null,
      'priority': 'medium',
      'status': 'todo',
      'due_date': null,
      'due_time': null,
      'estimated_minutes': null,
      'category': 'tasks',
      'completed_at': null,
      'created_at': now,
      'updated_at': now,
      ..._normalized(body),
    };
  }

  /// Trimmed title and `HH:MM:SS` times, as the backend returns them.
  static Map<String, dynamic> _normalized(Map<String, dynamic> body) => {
    ...body,
    if (body['title'] != null) 'title': (body['title'] as String).trim(),
    if (body['due_time'] != null)
      'due_time': (body['due_time'] as String).length == 5
          ? '${body['due_time']}:00'
          : body['due_time'],
  };

  static Map<String, dynamic> _taskOut(Map<String, dynamic> task) =>
      Map.of(task)..remove('owner');

  String _now() => DateTime.utc(
    2026,
    9,
    24,
    8,
  ).add(Duration(seconds: ++_ids)).toIso8601String();

  /// `DashboardOut`, measured against the profile's daily targets.
  Map<String, dynamic> _dashboard(String email) {
    final profile = profileOf(email)!;
    final open = [
      for (final task in tasksOf(email))
        if (task['status'] == 'todo') task,
    ];
    const streak = {'current': 0, 'longest': 0, 'active_today': false};
    return {
      'date': dateInZone[profile['timezone']] ?? dashboardDate,
      'greeting': 'morning',
      'display_name': profile['display_name'],
      'today': {
        'study_minutes': 0,
        'study_goal_minutes': profile['daily_study_goal_minutes'],
        'tasks_completed': tasksOf(email).length - open.length,
        'task_goal': profile['daily_task_goal'],
        'steps': 0,
        'step_goal': profile['daily_step_goal'],
        'workout_status': 'pending',
        'workout_minutes': 0,
        'sleep_minutes': null,
        'sleep_goal_minutes': profile['daily_sleep_goal_minutes'],
        'calories': 0,
        'calorie_goal': profile['daily_calorie_goal'],
        ...?_today[email],
      },
      'streaks': {
        for (final kind in ['study', 'tasks', 'fitness', 'balance'])
          kind: streak,
      },
      'next_exam': _nextExam[email],
      'upcoming_tasks': open.take(5).toList(),
      'study_today': <Object>[],
      'ai_plan': null,
    };
  }

  Map<String, dynamic> _user(String email) => {
    'id': _users[email]!['id'],
    'email': email,
    'created_at': '2026-09-24T08:00:00Z',
    'profile': Map.of(profileOf(email)!),
  };

  static const _targets = {
    'daily_study_goal_minutes': 960,
    'daily_step_goal': 100000,
    'daily_task_goal': 50,
    'daily_sleep_goal_minutes': 960,
    'daily_calorie_goal': 10000,
  };

  /// The backend's `ProfileUpdate` rules: only the fields sent change.
  http.Response _patchProfile(String email, Map<String, dynamic> body) {
    const nullable = {'username'};
    final fields = {
      'display_name',
      'timezone',
      'username',
      'preferred_workout_time',
      ..._targets.keys,
    };
    for (final MapEntry(:key, :value) in body.entries) {
      if (!fields.contains(key)) {
        return _invalid('body.$key', 'Extra inputs are not permitted');
      }
      if (value == null && !nullable.contains(key)) {
        return _invalid('body', 'These fields cannot be null: $key');
      }
    }
    final changes = Map.of(body);
    if (changes['display_name'] case final String name) {
      if (name.trim().isEmpty || name.trim().length > 60) {
        return _invalid('body.display_name', 'Enter 1 to 60 characters');
      }
      changes['display_name'] = name.trim();
    }
    if (changes['timezone'] case final String zone
        when !commonTimezones.contains(zone)) {
      return _invalid(
        'body.timezone',
        "Unknown timezone. Use an IANA name such as 'Asia/Kolkata'.",
      );
    }
    for (final MapEntry(:key, value: max) in _targets.entries) {
      if (changes[key] case final int n when n < 0 || n > max) {
        return _invalid('body.$key', 'Must be 0 to $max');
      }
    }
    if (changes['preferred_workout_time'] case final String time
        when !['morning', 'afternoon', 'evening'].contains(time)) {
      return _invalid('body.preferred_workout_time', 'Unknown value');
    }
    if (changes['username'] case final String name) {
      final handle = name.trim().toLowerCase();
      if (!RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(handle)) {
        return _invalid('body.username', 'String should match pattern');
      }
      final taken = _users.entries.any(
        (user) =>
            user.key != email && profileOf(user.key)!['username'] == handle,
      );
      if (taken) return _error(409, 'conflict', 'That username is taken');
      changes['username'] = handle;
    }
    profileOf(email)!.addAll(changes);
    return _json(profileOf(email)!);
  }

  Map<String, dynamic> _tokenResponse(String email) => {
    'access_token': _issue(email),
    'token_type': 'bearer',
    'expires_in': 43200,
    'user': _user(email),
  };

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static http.Response _error(int status, String code, String message) =>
      _json({
        'error': {'code': code, 'message': message},
      }, status);

  static http.Response _invalid(String field, String message) => _json({
    'error': {
      'code': 'validation_error',
      'message': 'Some fields are invalid',
      'details': [
        {'field': field, 'message': message},
      ],
    },
  }, 422);
}
