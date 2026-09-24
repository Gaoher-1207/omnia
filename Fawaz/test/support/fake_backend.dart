import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/token_store.dart';

/// An in-memory stand-in for the FastAPI backend, speaking the same JSON.
/// Enough of the contract for widget tests to drive the real app code:
/// ApiClient → repositories → controllers → screens.
class FakeBackend {
  FakeBackend({this.signedIn = true}) {
    if (signedIn) {
      _users['sam@example.com'] = _newUser('Sam', 'sam@example.com', 'password-123');
      tokens.token = 'token-sam';
      _tokens['token-sam'] = 'sam@example.com';
    }
  }

  final bool signedIn;
  final tokens = MemoryTokenStore();
  final requests = <String>[];
  bool offline = false;

  static final today = DateTime(2026, 9, 24);
  static String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final _users = <String, Map<String, dynamic>>{};
  final _tokens = <String, String>{};
  final tasks = <Map<String, dynamic>>[];
  final subjects = <Map<String, dynamic>>[];
  final exams = <Map<String, dynamic>>[];
  final topics = <Map<String, dynamic>>[];
  final sessions = <Map<String, dynamic>>[];
  final activity = <String, Map<String, dynamic>>{};
  final sleep = <String, Map<String, dynamic>>{};
  final meals = <Map<String, dynamic>>[];
  Map<String, dynamic>? plan;
  var _nextId = 0;
  String _id() => 'id-${++_nextId}';

  AppDependencies dependencies() => AppDependencies.forApi(
    ApiClient(baseUrl: 'http://omnia.test/api', tokens: tokens, httpClient: MockClient(handle)),
  );

  Map<String, dynamic> _newUser(String name, String email, String password) => {
    'id': _id(),
    'email': email,
    'password': password,
    'created_at': '2026-09-01T08:00:00Z',
    'profile': {
      'display_name': name,
      'timezone': 'Asia/Kolkata',
      'daily_study_goal_minutes': 240,
      'daily_step_goal': 8000,
      'daily_task_goal': 5,
      'preferred_workout_time': 'evening',
      'daily_sleep_goal_minutes': 480,
      'daily_calorie_goal': 2000,
      'username': null,
    },
  };

  Map<String, dynamic> _publicUser(Map<String, dynamic> u) =>
      {'id': u['id'], 'email': u['email'], 'created_at': u['created_at'], 'profile': u['profile']};

  http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _error(int status, String code, String message, [List<Map<String, String>> details = const []]) =>
      _json({
        'error': {'code': code, 'message': message, if (details.isNotEmpty) 'details': details},
      }, status);

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api', '');
    requests.add('${request.method} $path');
    if (offline) throw http.ClientException('offline');
    final body = request.body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
    final q = request.url.queryParameters;

    // --- auth (no token needed)
    if (request.method == 'POST' && path == '/auth/register') {
      final email = '${body['email']}'.toLowerCase();
      if ('${body['password']}'.length < 8) {
        return _error(422, 'validation_error', 'Some fields are invalid', [
          {'field': 'body.password', 'message': 'String should have at least 8 characters'},
        ]);
      }
      if (_users.containsKey(email)) return _error(409, 'conflict', 'An account with this email already exists');
      final user = _newUser('${body['display_name']}', email, '${body['password']}');
      (user['profile'] as Map)['timezone'] = body['timezone'];
      _users[email] = user;
      return _json(_token(email), 201);
    }
    if (request.method == 'POST' && path == '/auth/login') {
      final user = _users['${body['email']}'.toLowerCase()];
      if (user == null || user['password'] != body['password']) {
        return _error(401, 'unauthorized', 'Incorrect email or password');
      }
      return _json(_token(user['email'] as String));
    }

    final auth = request.headers['Authorization'] ?? '';
    final email = _tokens[auth.replaceFirst('Bearer ', '')];
    if (email == null) return _error(401, 'unauthorized', 'Your session has expired or is invalid. Please sign in again.');
    final me = _users[email]!;
    final profile = Map<String, dynamic>.from(me['profile'] as Map);

    switch ((request.method, path)) {
      case ('GET', '/auth/me'):
        return _json(_publicUser(me));
      case ('POST', '/auth/logout-all'):
        _tokens.removeWhere((_, e) => e == email);
        return http.Response('', 204);
      case ('PATCH', '/profile'):
        profile.addAll(body);
        me['profile'] = profile;
        return _json(profile);
      case ('GET', '/dashboard'):
        return _json(_dashboard(profile));
      case ('GET', '/tasks'):
        final offset = int.parse(q['offset'] ?? '0');
        final limit = int.parse(q['limit'] ?? '50');
        return _json({
          'items': tasks.skip(offset).take(limit).toList(),
          'total': tasks.length,
          'limit': limit,
          'offset': offset,
        });
      case ('POST', '/tasks'):
        final task = {
          ...body,
          'id': _id(),
          'status': 'todo',
          'completed_at': null,
          'created_at': '2026-09-24T03:00:00Z',
          'updated_at': '2026-09-24T03:00:00Z',
        };
        task.putIfAbsent('category', () => 'tasks');
        tasks.add(task);
        return _json(task, 201);
      case ('GET', '/study/subjects'):
        return _json(subjects);
      case ('POST', '/study/subjects'):
        if (subjects.any((s) => s['name'] == body['name'])) {
          return _error(409, 'conflict', 'You already have a subject with this name');
        }
        final subject = {'id': _id(), 'name': body['name'], 'color': body['color'], 'created_at': '2026-09-24T03:00:00Z'};
        subjects.add(subject);
        return _json(subject, 201);
      case ('GET', '/study/exams'):
        return _json(exams);
      case ('POST', '/study/exams'):
        final exam = {
          'id': _id(),
          'title': body['title'],
          'exam_date': body['exam_date'],
          'notes': null,
          'subject': _subjectRef(body['subject_id'] as String),
          'days_left': DateTime.parse(body['exam_date'] as String).difference(today).inDays,
        };
        exams.add(exam);
        return _json(exam, 201);
      case ('GET', '/study/backlog'):
        final subject = q['subject_id'];
        return _json(topics.where((t) => subject == null || (t['subject'] as Map)['id'] == subject).toList());
      case ('POST', '/study/backlog'):
        final topic = {
          'id': _id(),
          'title': body['title'],
          'kind': body['kind'] ?? 'backlog',
          'status': 'pending',
          'estimated_minutes': body['estimated_minutes'] ?? 60,
          'completed_at': null,
          'created_at': '2026-09-24T03:00:00Z',
          'subject': _subjectRef(body['subject_id'] as String),
        };
        topics.add(topic);
        return _json(topic, 201);
      case ('GET', '/study/sessions'):
        return _json(sessions);
      case ('POST', '/study/sessions'):
        final subjectId = body['subject_id'] as String?;
        final session = {
          'id': _id(),
          'session_date': day(today),
          'duration_minutes': body['duration_minutes'],
          'notes': null,
          'backlog_item_id': body['backlog_item_id'],
          'subject': subjectId == null ? null : _subjectRef(subjectId),
          'created_at': '2026-09-24T04:00:00Z',
        };
        sessions.add(session);
        return _json(session, 201);
      case ('GET', '/study/plan'):
        return _json(_studyPlan(profile));
      case ('GET', '/activity'):
        return _json({
          'start': q['from'],
          'end': q['to'],
          'step_goal': profile['daily_step_goal'],
          'days': [
            for (var i = 13; i >= 0; i--) _activityDay(day(today.subtract(Duration(days: i)))),
          ],
        });
      case ('GET', '/meals'):
        return _json({
          'day': q['day'] ?? day(today),
          'calorie_goal': profile['daily_calorie_goal'],
          'totals': {'calories': _calories(), 'protein_g': 0, 'carbs_g': 0, 'fat_g': 0},
          'meals': meals,
        });
      case ('POST', '/meals'):
        final meal = {...body, 'id': _id(), 'day': day(today), 'created_at': '2026-09-24T05:00:00Z'};
        for (final k in ['protein_g', 'carbs_g', 'fat_g']) {
          meal.putIfAbsent(k, () => 0);
        }
        meals.add(meal);
        return _json(meal, 201);
      case ('POST', '/nutrition/estimate'):
        return _error(503, 'service_unavailable', "Food photo analysis isn't set up on this server yet.");
      case ('GET', '/progress'):
        return _json({'date': day(today), 'streaks': _streaks(), 'history': _history(int.parse(q['days'] ?? '14'))});
      case ('GET', '/achievements'):
        return _json([
          {
            'code': 'first_study',
            'title': 'First step',
            'description': 'Log your first study session',
            'earned': sessions.isNotEmpty,
            'progress': sessions.isEmpty ? 0 : 1,
            'target': 1,
          },
        ]);
      case ('GET', '/ai/daily-plan'):
        return plan == null ? _error(404, 'not_found', 'Plan not found') : _json(plan);
      case ('POST', '/ai/daily-plan'):
        final created = plan == null || body['regenerate'] == true;
        if (created) plan = _makePlan(body['note'] as String?);
        return _json(plan, created ? 201 : 200);
      case ('GET', '/social/friends'):
        return _json({'friends': [], 'incoming': [], 'outgoing': []});
      case ('GET', '/social/groups'):
        return _json([]);
      case ('GET', '/social/feed'):
        return _json([]);
    }

    // parameterised routes
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length == 2 && segments[0] == 'tasks') {
      final index = tasks.indexWhere((t) => t['id'] == segments[1]);
      if (index < 0) return _error(404, 'not_found', 'Task not found');
      if (request.method == 'DELETE') {
        tasks.removeAt(index);
        return http.Response('', 204);
      }
      if (request.method == 'PATCH') {
        final task = {...tasks[index], ...body};
        if (body['status'] == 'done') task['completed_at'] = '2026-09-24T06:00:00Z';
        if (body['status'] == 'todo') task['completed_at'] = null;
        tasks[index] = task;
        return _json(task);
      }
      return _json(tasks[index]);
    }
    if (segments.length == 3 && segments[0] == 'study' && segments[1] == 'backlog' && request.method == 'PATCH') {
      final topic = topics.firstWhere((t) => t['id'] == segments[2]);
      topic.addAll(body);
      return _json(topic);
    }
    if (segments.length == 3 && segments[0] == 'study' && segments[1] == 'sessions' && request.method == 'DELETE') {
      sessions.removeWhere((s) => s['id'] == segments[2]);
      return http.Response('', 204);
    }
    if (segments.length == 2 && segments[0] == 'activity') {
      if (request.method == 'PUT') {
        activity[segments[1]] = {...body, 'id': 'act-${segments[1]}', 'day': segments[1], 'updated_at': null};
      }
      return _json(_activityDay(segments[1]));
    }
    if (segments.length == 2 && segments[0] == 'sleep') {
      if (request.method == 'PUT') {
        sleep[segments[1]] = {...body, 'id': 'sleep-${segments[1]}', 'day': segments[1], 'logged': true};
      }
      return _json(sleep[segments[1]] ?? {'day': segments[1], 'duration_minutes': 0, 'logged': false});
    }
    return _error(404, 'not_found', 'Not found');
  }

  Map<String, dynamic> _token(String email) {
    final token = 'token-${_tokens.length + 1}-$email';
    _tokens[token] = email;
    return {
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': 43200,
      'user': _publicUser(_users[email]!),
    };
  }

  /// Expire every token, as if AUTH_SECRET changed or "sign out everywhere" ran.
  void expireSessions() => _tokens.clear();

  Map<String, dynamic> _subjectRef(String id) {
    final s = subjects.firstWhere((s) => s['id'] == id);
    return {'id': s['id'], 'name': s['name'], 'color': s['color']};
  }

  Map<String, dynamic> _activityDay(String d) =>
      activity[d] ?? {'id': null, 'day': d, 'steps': 0, 'workout_done': false, 'workout_minutes': 0, 'workout_type': null, 'updated_at': null};

  int _studyToday() => sessions.fold<int>(0, (sum, s) => sum + (s['duration_minutes'] as int));
  int _calories() => meals.fold<int>(0, (sum, m) => sum + (m['calories'] as int));
  int _tasksDone() => tasks.where((t) => t['status'] == 'done').length;

  Map<String, dynamic> _streak(bool active) => {'current': active ? 1 : 0, 'longest': active ? 1 : 0, 'active_today': active};

  Map<String, dynamic> _streaks() {
    final act = _activityDay(day(today));
    return {
      'study': _streak(sessions.isNotEmpty),
      'tasks': _streak(_tasksDone() > 0),
      'fitness': _streak(act['workout_done'] == true),
      'balance': _streak(sessions.isNotEmpty && _tasksDone() > 0),
    };
  }

  List<Map<String, dynamic>> _history(int days) => [
    for (var i = days - 1; i >= 0; i--)
      {
        'date': day(today.subtract(Duration(days: i))),
        'study_minutes': i == 0 ? _studyToday() : 0,
        'tasks_completed': i == 0 ? _tasksDone() : 0,
        'steps': _activityDay(day(today.subtract(Duration(days: i))))['steps'],
        'workout_done': _activityDay(day(today.subtract(Duration(days: i))))['workout_done'],
        'balanced': i == 0 && sessions.isNotEmpty && _tasksDone() > 0,
        'sleep_minutes': sleep[day(today.subtract(Duration(days: i)))]?['duration_minutes'],
        'calories': i == 0 ? _calories() : 0,
      },
  ];

  List<Map<String, dynamic>> _blocks() => [
    for (final t in topics.where((t) => t['status'] == 'pending'))
      {
        'subject_id': (t['subject'] as Map)['id'],
        'subject_name': (t['subject'] as Map)['name'],
        'backlog_item_id': t['id'],
        'title': t['title'],
        'minutes': t['estimated_minutes'],
        'reason': 'Clearing backlog',
      },
  ];

  Map<String, dynamic> _studyPlan(Map<String, dynamic> profile) => {
    'start_date': day(today),
    'unscheduled_minutes': 0,
    'warnings': [],
    'days': [
      for (var i = 0; i < 7; i++)
        {
          'date': day(today.add(Duration(days: i))),
          'available_minutes': profile['daily_study_goal_minutes'],
          'planned_minutes': i == 0 ? _blocks().fold<int>(0, (s, b) => s + (b['minutes'] as int)) : 0,
          'blocks': i == 0 ? _blocks() : [],
          'exams': [],
        },
    ],
  };

  Map<String, dynamic> _dashboard(Map<String, dynamic> profile) {
    final act = _activityDay(day(today));
    final exam = exams.isEmpty ? null : exams.first;
    return {
      'date': day(today),
      'greeting': 'morning',
      'display_name': profile['display_name'],
      'today': {
        'study_minutes': _studyToday(),
        'study_goal_minutes': profile['daily_study_goal_minutes'],
        'tasks_completed': _tasksDone(),
        'task_goal': profile['daily_task_goal'],
        'steps': act['steps'],
        'step_goal': profile['daily_step_goal'],
        'workout_status': act['workout_done'] == true ? 'done' : 'pending',
        'workout_minutes': act['workout_minutes'],
        'sleep_minutes': sleep[day(today)]?['duration_minutes'],
        'sleep_goal_minutes': profile['daily_sleep_goal_minutes'],
        'calories': _calories(),
        'calorie_goal': profile['daily_calorie_goal'],
      },
      'streaks': _streaks(),
      'next_exam': exam == null
          ? null
          : {
              'id': exam['id'],
              'title': exam['title'],
              'subject_name': (exam['subject'] as Map)['name'],
              'exam_date': exam['exam_date'],
              'days_left': exam['days_left'],
            },
      'upcoming_tasks': tasks.where((t) => t['status'] == 'todo').take(5).toList(),
      'study_today': _blocks(),
      'ai_plan': plan,
    };
  }

  Map<String, dynamic> _makePlan(String? note) {
    final subject = subjects.isEmpty ? null : subjects.first;
    final task = tasks.isEmpty ? null : tasks.first;
    return {
      'id': _id(),
      'plan_date': day(today),
      'source': 'rules',
      'is_fallback': false,
      'created_at': '2026-09-24T03:00:00Z',
      'summary': 'A balanced day across study, tasks and fitness.',
      'items': [
        {
          'start': '23:00',
          'end': '23:45',
          'category': 'study',
          'title': subject == null ? 'General study' : '${subject['name']}: Revision',
          'detail': 'Exam in 5 days',
          'task_id': null,
          'subject_id': subject?['id'],
        },
        if (task != null)
          {
            'start': '23:50',
            'end': '23:59',
            'category': 'task',
            'title': task['title'],
            'detail': 'High priority',
            'task_id': task['id'],
            'subject_id': null,
          },
      ],
      'tips': ['Drink water.'],
      'adjustments': [if (note != null) 'You mentioned: $note'],
    };
  }
}
