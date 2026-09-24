import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/social/domain/social.dart';

/// Friends, groups, chat, feed and challenges (`/api/social/...`).
class SocialRepository {
  SocialRepository(this._api);
  final ApiClient _api;

  Future<FriendsOverview> friends() async =>
      FriendsOverview.fromJson(asMap(await _api.get('/social/friends')));

  Future<FriendsOverview> requestFriend(String username) async => FriendsOverview.fromJson(
    asMap(await _api.post('/social/friends/requests', body: {'username': username.trim()})),
  );

  Future<FriendsOverview> respond(String requestId, {required bool accept}) async =>
      FriendsOverview.fromJson(
        asMap(
          await _api.post('/social/friends/requests/$requestId/${accept ? 'accept' : 'decline'}'),
        ),
      );

  Future<void> removeFriend(String userId) => _api.delete('/social/friends/$userId');

  Future<List<Group>> groups() async => [
    for (final g in asMapList(await _api.get('/social/groups'))) Group.fromJson(g),
  ];

  Future<Group> createGroup(String name, {String? description}) async => Group.fromJson(
    asMap(await _api.post('/social/groups', body: {'name': name.trim(), 'description': description})),
  );

  Future<Group> group(String id) async => Group.fromJson(asMap(await _api.get('/social/groups/$id')));

  Future<Group> addMember(String groupId, String userId) async => Group.fromJson(
    asMap(await _api.post('/social/groups/$groupId/members', body: {'user_id': userId})),
  );

  Future<void> removeMember(String groupId, String userId) =>
      _api.delete('/social/groups/$groupId/members/$userId');

  Future<void> deleteGroup(String groupId) => _api.delete('/social/groups/$groupId');

  Future<List<ChatMessage>> messages(String groupId, {String? after}) async => [
    for (final m in asMapList(
      await _api.get('/social/groups/$groupId/messages', query: {'after': after}),
    ))
      ChatMessage.fromJson(m),
  ];

  Future<ChatMessage> sendMessage(String groupId, String body) async => ChatMessage.fromJson(
    asMap(await _api.post('/social/groups/$groupId/messages', body: {'body': body.trim()})),
  );

  Future<List<Post>> feed() async => [
    for (final p in asMapList(await _api.get('/social/feed'))) Post.fromJson(p),
  ];

  /// [share] picks which of today's numbers to include; the server reads the
  /// values itself, so the app can't post numbers that aren't real.
  Future<Post> shareProgress({required List<String> share, String? text, String? groupId}) async =>
      _post({'kind': 'progress', 'share': share, 'text': text, 'group_id': groupId});

  Future<Post> shareAchievement(String code, {String? text, String? groupId}) async =>
      _post({'kind': 'achievement', 'achievement_code': code, 'text': text, 'group_id': groupId});

  Future<Post> shareText(String text, {String? groupId}) async =>
      _post({'kind': 'text', 'text': text, 'group_id': groupId});

  Future<Post> _post(Map<String, Object?> body) async =>
      Post.fromJson(asMap(await _api.post('/social/posts', body: body)));

  Future<void> deletePost(String id) => _api.delete('/social/posts/$id');

  Future<Post> like(String postId, {required bool liked}) async => Post.fromJson(
    asMap(
      liked
          ? await _api.post('/social/posts/$postId/like')
          : await _api.delete('/social/posts/$postId/like'),
    ),
  );

  Future<List<Challenge>> challenges(String groupId) async => [
    for (final c in asMapList(await _api.get('/social/groups/$groupId/challenges')))
      Challenge.fromJson(c),
  ];

  Future<Challenge> createChallenge(
    String groupId, {
    required String title,
    required ChallengeMetric metric,
    required int target,
    required DateTime start,
    required DateTime end,
  }) async => Challenge.fromJson(
    asMap(
      await _api.post(
        '/social/groups/$groupId/challenges',
        body: {
          'title': title.trim(),
          'metric': challengeMetricApi[metric],
          'target': target,
          'start_date': formatDay(start),
          'end_date': formatDay(end),
        },
      ),
    ),
  );

  Future<Challenge> setJoined(String challengeId, {required bool join}) async => Challenge.fromJson(
    asMap(
      join
          ? await _api.post('/social/challenges/$challengeId/join')
          : await _api.delete('/social/challenges/$challengeId/join'),
    ),
  );
}
