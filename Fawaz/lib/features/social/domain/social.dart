import 'package:omnia_ui/core/models/user.dart';

class PublicUser {
  const PublicUser({required this.id, required this.displayName, this.username});
  final String id, displayName;
  final String? username;

  String get handle => username == null ? displayName : '@$username';

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
    username: json['username'] as String?,
  );
}

class FriendRequest {
  const FriendRequest({required this.id, required this.user});
  final String id;
  final PublicUser user;
}

class FriendsOverview {
  const FriendsOverview({required this.friends, required this.incoming, required this.outgoing});
  final List<PublicUser> friends;
  final List<FriendRequest> incoming, outgoing;

  factory FriendsOverview.fromJson(Map<String, dynamic> json) {
    List<FriendRequest> requests(String key) => [
      for (final r in asMapList(json[key]))
        FriendRequest(id: r['id'] as String, user: PublicUser.fromJson(asMap(r['user']))),
    ];
    return FriendsOverview(
      friends: [for (final f in asMapList(json['friends'])) PublicUser.fromJson(f)],
      incoming: requests('incoming'),
      outgoing: requests('outgoing'),
    );
  }
}

class GroupMember {
  const GroupMember({required this.user, required this.isOwner});
  final PublicUser user;
  final bool isOwner;
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.memberCount,
    this.description,
    this.members = const [],
  });
  final String id, name;
  final String? description;
  final bool isOwner;
  final int memberCount;
  final List<GroupMember> members;

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    isOwner: json['my_role'] == 'owner',
    memberCount: json['member_count'] as int,
    members: [
      for (final m in asMapList(json['members'] ?? const []))
        GroupMember(user: PublicUser.fromJson(asMap(m['user'])), isOwner: m['role'] == 'owner'),
    ],
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
    required this.createdAtRaw,
    required this.mine,
  });
  final String id, body;
  final PublicUser sender;
  final DateTime createdAt;

  /// Exact server timestamp, used as the polling cursor.
  final String createdAtRaw;
  final bool mine;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    sender: PublicUser.fromJson(asMap(json['sender'])),
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    createdAtRaw: json['created_at'] as String,
    mine: json['mine'] as bool,
  );
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.kind,
    required this.body,
    required this.payload,
    required this.groupName,
    required this.likeCount,
    required this.likedByMe,
    required this.mine,
    required this.createdAt,
  });
  final String id, kind;
  final PublicUser author;
  final String? body, groupName;
  final Map<String, dynamic> payload;
  final int likeCount;
  final bool likedByMe, mine;
  final DateTime createdAt;

  /// Readable lines for the numbers a progress post shared.
  List<String> get highlights {
    if (kind == 'achievement') return ['🏅 ${payload['title']}: ${payload['description']}'];
    final lines = <String>[];
    final study = payload['study_minutes'];
    if (study is int) lines.add('Studied ${study ~/ 60}h ${study % 60}m');
    final tasks = payload['tasks_completed'];
    if (tasks is int) lines.add('$tasks tasks done');
    final steps = payload['steps'];
    if (steps is int) lines.add('$steps steps');
    if (payload['workout_done'] == true) lines.add('Workout done');
    for (final key in ['study_streak', 'balance_streak', 'fitness_streak']) {
      final value = payload[key];
      if (value is int) lines.add('$value-day ${key.split('_').first} streak');
    }
    return lines;
  }

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as String,
    author: PublicUser.fromJson(asMap(json['author'])),
    kind: json['kind'] as String,
    body: json['body'] as String?,
    payload: asMap(json['payload']),
    groupName: json['group_name'] as String?,
    likeCount: json['like_count'] as int,
    likedByMe: json['liked_by_me'] as bool,
    mine: json['mine'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}

enum ChallengeMetric { studyMinutes, studySessions, steps, tasksCompleted, workouts }

const challengeMetricApi = {
  ChallengeMetric.studyMinutes: 'study_minutes',
  ChallengeMetric.studySessions: 'study_sessions',
  ChallengeMetric.steps: 'steps',
  ChallengeMetric.tasksCompleted: 'tasks_completed',
  ChallengeMetric.workouts: 'workouts',
};

const challengeMetricLabel = {
  ChallengeMetric.studyMinutes: 'Study minutes',
  ChallengeMetric.studySessions: 'Study sessions',
  ChallengeMetric.steps: 'Steps',
  ChallengeMetric.tasksCompleted: 'Tasks completed',
  ChallengeMetric.workouts: 'Workouts',
};

class LeaderboardRow {
  const LeaderboardRow({required this.user, required this.value, required this.completed});
  final PublicUser user;
  final int value;
  final bool completed;
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    required this.start,
    required this.end,
    required this.joined,
    required this.groupTotal,
    required this.leaderboard,
  });
  final String id, title;
  final ChallengeMetric metric;
  final int target, groupTotal;
  final DateTime start, end;
  final bool joined;
  final List<LeaderboardRow> leaderboard;

  factory Challenge.fromJson(Map<String, dynamic> json) {
    final metricName = json['metric'] as String;
    return Challenge(
      id: json['id'] as String,
      title: json['title'] as String,
      metric: challengeMetricApi.entries
          .firstWhere((e) => e.value == metricName, orElse: () => challengeMetricApi.entries.first)
          .key,
      target: json['target'] as int,
      start: parseDay(json['start_date'] as String),
      end: parseDay(json['end_date'] as String),
      joined: json['joined'] as bool,
      groupTotal: json['group_total'] as int,
      leaderboard: [
        for (final row in asMapList(json['leaderboard']))
          LeaderboardRow(
            user: PublicUser.fromJson(asMap(row['user'])),
            value: row['value'] as int,
            completed: row['completed'] as bool,
          ),
      ],
    );
  }
}
