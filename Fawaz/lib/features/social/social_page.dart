import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/settings/goals_page.dart';
import 'package:omnia_ui/features/social/domain/social.dart';
import 'package:omnia_ui/features/social/group_page.dart';

enum _Tab { feed, friends, groups }

String timeAgo(DateTime moment) {
  final diff = DateTime.now().difference(moment);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Friends, groups and the progress feed. Nothing here is public: friends
/// are mutual, groups are invite-only, and posts share only what you pick.
class SocialPage extends StatefulWidget {
  const SocialPage({super.key});
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  late final deps = AppDependenciesScope.of(context);
  late final feed = Loadable<List<Post>>(() => deps.social.feed())..load();
  late final friends = Loadable<FriendsOverview>(() => deps.social.friends())..load();
  late final groups = Loadable<List<Group>>(() => deps.social.groups())..load();
  var _tab = _Tab.feed;

  @override
  void dispose() {
    feed.dispose();
    friends.dispose();
    groups.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {Loadable<Object?>? reload, String? done}) async {
    try {
      await action();
      await reload?.load();
      if (done != null && mounted) showDone(context, done);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.w900))),
    floatingActionButton: _tab == _Tab.friends
        ? null
        : FloatingActionButton.extended(
            onPressed: _tab == _Tab.feed ? _share : _createGroup,
            backgroundColor: context.actionBackground,
            foregroundColor: context.actionForeground,
            icon: Icon(_tab == _Tab.feed ? Icons.ios_share : Icons.group_add_outlined),
            label: Text(_tab == _Tab.feed ? 'Share progress' : 'New group', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 8), child: _switcher(context)),
          Expanded(
            child: switch (_tab) {
              _Tab.feed => _feedView(),
              _Tab.friends => _friendsView(),
              _Tab.groups => _groupsView(),
            },
          ),
        ],
      ),
    ),
  );

  Widget _switcher(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: SurfaceStyle.of(context).decoration(
      color: context.colors.surfaceContainerHighest,
      radius: 12,
      offset: const Offset(2, 2),
    ),
    child: Row(
      children: [
        for (final (tab, name) in [(_Tab.feed, 'Feed'), (_Tab.friends, 'Friends'), (_Tab.groups, 'Groups')])
          Expanded(
            child: Material(
              color: _tab == tab ? context.cardColor(lilac) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => setState(() => _tab = tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _tab == tab ? context.cardForeground(lilac) : context.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ------------------------------------------------------------------ feed

  Widget _feedView() => ListenableBuilder(
    listenable: feed,
    builder: (context, _) {
      final posts = feed.data;
      if (posts == null) {
        return feed.error == null ? const LoadingView() : ErrorView(error: feed.error!, onRetry: feed.load);
      }
      return RefreshIndicator(
        onRefresh: feed.load,
        child: posts.isEmpty
            ? ListView(
                children: const [
                  MessageView(
                    title: 'Your feed is quiet',
                    detail: 'Add friends by username, then share your progress. Only the numbers you pick are shared.',
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                children: [for (final post in posts) _postCard(post)],
              ),
      );
    },
  );

  Widget _postCard(Post post) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HardCard(
      shadowOffset: const Offset(2, 3),
      color: post.kind == 'achievement' ? yellow : paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${post.author.displayName} · ${timeAgo(post.createdAt)}'
                  '${post.groupName == null ? '' : ' · ${post.groupName}'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (post.mine)
                IconButton(
                  tooltip: 'Delete post',
                  onPressed: () => _run(() => deps.social.deletePost(post.id), reload: feed),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          for (final line in post.highlights) Text(line, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (post.body != null) ...[const SizedBox(height: 4), Text(post.body!)],
          Row(
            children: [
              IconButton(
                tooltip: post.likedByMe ? 'Unlike' : 'Like',
                onPressed: () => _run(() => deps.social.like(post.id, liked: !post.likedByMe), reload: feed),
                icon: Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border),
              ),
              Text('${post.likeCount}'),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _share() async {
    final groupList = groups.data ?? const <Group>[];
    final choice = await showModalBottomSheet<_ShareChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShareSheet(groups: groupList),
    );
    if (choice == null) return;
    await _run(
      () => deps.social.shareProgress(share: choice.fields, text: choice.text, groupId: choice.groupId),
      reload: feed,
      done: 'Shared.',
    );
  }

  // --------------------------------------------------------------- friends

  Widget _friendsView() {
    final me = AuthScope.of(context).user;
    return ListenableBuilder(
      listenable: friends,
      builder: (context, _) {
        final data = friends.data;
        if (data == null) {
          return friends.error == null ? const LoadingView() : ErrorView(error: friends.error!, onRetry: friends.load);
        }
        return RefreshIndicator(
          onRefresh: friends.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              HardCard(
                color: lilac,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me?.profile.username == null
                          ? 'Set a username so friends can find you.'
                          : 'Your username: @${me!.profile.username}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SolidAction(
                            label: 'Add a friend',
                            onTap: me?.profile.username == null ? _setUsername : _addFriend,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (data.incoming.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                for (final request in data.incoming)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(request.user.displayName),
                    subtitle: Text(request.user.handle),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Accept',
                          onPressed: () => _run(() => deps.social.respond(request.id, accept: true), reload: friends),
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Decline',
                          onPressed: () => _run(() => deps.social.respond(request.id, accept: false), reload: friends),
                          icon: const Icon(Icons.cancel_outlined),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              Text('Friends (${data.friends.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              if (data.friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('No friends yet.', style: TextStyle(color: context.mutedForeground)),
                ),
              for (final friend in data.friends)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(friend.displayName.characters.first.toUpperCase())),
                  title: Text(friend.displayName),
                  subtitle: Text(friend.handle),
                  trailing: IconButton(
                    tooltip: 'Remove friend',
                    onPressed: () => _run(() => deps.social.removeFriend(friend.id), reload: friends),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ),
              if (data.outgoing.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Sent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                for (final request in data.outgoing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(request.user.displayName),
                    subtitle: Text('${request.user.handle} · waiting'),
                    trailing: TextButton(
                      onPressed: () => _run(() => deps.social.removeFriend(request.user.id), reload: friends),
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _setUsername() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const GoalsPage()));
  }

  Future<void> _addFriend() async {
    final username = await showDialog<String>(context: context, builder: (_) => const _UsernameDialog());
    if (username == null) return;
    await _run(() => deps.social.requestFriend(username), reload: friends, done: 'Request sent.');
  }

  // ---------------------------------------------------------------- groups

  Widget _groupsView() => ListenableBuilder(
    listenable: groups,
    builder: (context, _) {
      final list = groups.data;
      if (list == null) {
        return groups.error == null ? const LoadingView() : ErrorView(error: groups.error!, onRetry: groups.load);
      }
      return RefreshIndicator(
        onRefresh: groups.load,
        child: list.isEmpty
            ? ListView(
                children: const [
                  MessageView(
                    title: 'No groups yet',
                    detail: 'Start a study squad with friends: chat, share progress and run challenges.',
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                children: [
                  for (final group in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HardCard(
                        shadowOffset: const Offset(2, 3),
                        color: blue,
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(builder: (_) => GroupPage(groupId: group.id, name: group.name)),
                          );
                          await groups.load();
                        },
                        child: Row(
                          children: [
                            const Icon(Icons.groups_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(group.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                                  Text(
                                    '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}'
                                    '${group.isOwner ? ' · you own it' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      );
    },
  );

  Future<void> _createGroup() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _GroupNameDialog());
    if (name == null) return;
    await _run(() => deps.social.createGroup(name), reload: groups);
  }
}

class _ShareChoice {
  const _ShareChoice(this.fields, this.text, this.groupId);
  final List<String> fields;
  final String? text, groupId;
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.groups});
  final List<Group> groups;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  static const _options = {
    'study_minutes': 'Study time today',
    'tasks_completed': 'Tasks done today',
    'steps': 'Steps today',
    'workout_done': 'Workout done',
    'study_streak': 'Study streak',
    'balance_streak': 'Balance streak',
    'fitness_streak': 'Fitness streak',
  };
  final _selected = <String>{'study_minutes', 'balance_streak'};
  final _text = TextEditingController();
  String? _group;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text('Share today’s progress', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Only what you tick is shared. Numbers come from what you’ve logged.',
            style: TextStyle(color: context.mutedForeground)),
        for (final entry in _options.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _selected.contains(entry.key),
            title: Text(entry.value),
            onChanged: (v) => setState(() => v == true ? _selected.add(entry.key) : _selected.remove(entry.key)),
          ),
        TextField(
          controller: _text,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Add a note (optional)'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _group,
          decoration: const InputDecoration(labelText: 'Share with'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All my friends')),
            for (final g in widget.groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
          ],
          onChanged: (v) => setState(() => _group = v),
        ),
        const SizedBox(height: 16),
        SolidAction(
          label: 'Share',
          onTap: _selected.isEmpty
              ? () {}
              : () => Navigator.pop(
                  context,
                  _ShareChoice(_selected.toList(), _text.text.trim().isEmpty ? null : _text.text.trim(), _group),
                ),
        ),
      ],
    ),
  );
}

class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog();
  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a friend'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Their username', prefixText: '@'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: const Text('Send request'),
      ),
    ],
  );
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog();
  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New group'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Study Squad'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: const Text('Create'),
      ),
    ],
  );
}
