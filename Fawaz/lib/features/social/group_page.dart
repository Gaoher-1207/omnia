import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/social/domain/social.dart';

enum _Section { chat, challenges, members }

/// One group: chat (refreshed every few seconds while open), challenges and members.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.groupId, required this.name});
  final String groupId, name;
  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  late final deps = AppDependenciesScope.of(context);
  late final group = Loadable<Group>(() => deps.social.group(widget.groupId))..load();
  late final challenges = Loadable<List<Challenge>>(() => deps.social.challenges(widget.groupId))..load();
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  Object? _chatError;
  bool _chatLoaded = false, _sending = false;
  var _section = _Section.chat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshChat();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshChat());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    group.dispose();
    challenges.dispose();
    super.dispose();
  }

  Future<void> _refreshChat() async {
    if (!mounted || _section != _Section.chat && _chatLoaded) return;
    try {
      final after = _messages.isEmpty ? null : _messages.last.createdAtRaw;
      final fresh = await deps.social.messages(widget.groupId, after: after);
      if (!mounted) return;
      final known = {for (final m in _messages) m.id};
      setState(() {
        _messages.addAll(fresh.where((m) => !known.contains(m.id)));
        _chatLoaded = true;
        _chatError = null;
      });
      if (fresh.isNotEmpty) _scrollToEnd();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isNotFound) {
        // Removed from the group (or it was deleted): leave the screen.
        _poll?.cancel();
        showDone(context, 'You’re no longer in this group.');
        Navigator.pop(context);
        return;
      }
      if (!_chatLoaded) setState(() => _chatError = error);
    }
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await deps.social.sendMessage(widget.groupId, text);
      _input.clear();
      if (mounted && !_messages.any((m) => m.id == sent.id)) {
        setState(() => _messages.add(sent));
        _scrollToEnd();
      }
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _run(Future<void> Function() action, Loadable<Object?> reload) async {
    try {
      await action();
      await reload.load();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    appBar: AppBar(title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w900))),
    body: SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 8), child: _switcher(context)),
          Expanded(
            child: switch (_section) {
              _Section.chat => _chat(),
              _Section.challenges => _challenges(),
              _Section.members => _members(),
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
        for (final (section, name) in [
          (_Section.chat, 'Chat'),
          (_Section.challenges, 'Challenges'),
          (_Section.members, 'Members'),
        ])
          Expanded(
            child: Material(
              color: _section == section ? context.cardColor(lilac) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  setState(() => _section = section);
                  if (section == _Section.chat) _refreshChat();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _section == section ? context.cardForeground(lilac) : context.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ------------------------------------------------------------------ chat

  Widget _chat() {
    if (!_chatLoaded) {
      return _chatError == null ? const LoadingView() : ErrorView(error: _chatError!, onRetry: _refreshChat);
    }
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const MessageView(title: 'No messages yet', detail: 'Say hi to the group.')
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    return Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: HardCard(
                            shadowOffset: const Offset(1, 2),
                            color: m.mine ? blue : paper,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!m.mine)
                                  Text(m.sender.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                Text(m.body),
                                Text(
                                  '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Message', counterText: ''),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: context.actionBackground,
                  foregroundColor: context.actionForeground,
                ),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ challenges

  Widget _challenges() => ListenableBuilder(
    listenable: challenges,
    builder: (context, _) {
      final list = challenges.data;
      if (list == null) {
        return challenges.error == null
            ? const LoadingView()
            : ErrorView(error: challenges.error!, onRetry: challenges.load);
      }
      return RefreshIndicator(
        onRefresh: challenges.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            SolidAction(label: 'Start a challenge', onTap: _newChallenge),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const MessageView(
                title: 'No challenges yet',
                detail: 'Set a group goal, like 20 study sessions this week. Only people who join are counted.',
              ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HardCard(
                  color: mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      Text(
                        '${challengeMetricLabel[c.metric]} · target ${thousands(c.target)} each · '
                        '${longDate(c.start)} – ${longDate(c.end)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text('Group total: ${thousands(c.groupTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      for (final row in c.leaderboard)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text('${row.user.displayName}${row.completed ? '  ✓' : ''}')),
                              Text(thousands(row.value)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _run(() => deps.social.setJoined(c.id, join: !c.joined), challenges),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cardForeground(mint),
                          side: BorderSide(color: context.outline, width: 1.5),
                        ),
                        child: Text(c.joined ? 'Leave (stop sharing my number)' : 'Join (share my number)'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _newChallenge() async {
    final input = await showDialog<_ChallengeInput>(context: context, builder: (_) => const _ChallengeDialog());
    if (input == null) return;
    await _run(
      () => deps.social.createChallenge(
        widget.groupId,
        title: input.title,
        metric: input.metric,
        target: input.target,
        start: input.start,
        end: input.end,
      ),
      challenges,
    );
  }

  // --------------------------------------------------------------- members

  Widget _members() => ListenableBuilder(
    listenable: group,
    builder: (context, _) {
      final g = group.data;
      if (g == null) {
        return group.error == null ? const LoadingView() : ErrorView(error: group.error!, onRetry: group.load);
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          if (g.isOwner) ...[
            SolidAction(label: 'Add a friend', onTap: () => _addMember(g)),
            const SizedBox(height: 10),
          ],
          for (final m in g.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(m.user.displayName.characters.first.toUpperCase())),
              title: Text(m.user.displayName),
              subtitle: Text('${m.user.handle}${m.isOwner ? ' · owner' : ''}'),
              trailing: g.isOwner && !m.isOwner
                  ? IconButton(
                      tooltip: 'Remove from group',
                      onPressed: () => _run(() => deps.social.removeMember(g.id, m.user.id), group),
                      icon: const Icon(Icons.person_remove_outlined),
                    )
                  : null,
            ),
          const SizedBox(height: 16),
          if (g.isOwner)
            TextButton.icon(
              onPressed: () => _leaveOrDelete(g),
              icon: Icon(Icons.delete_outline, color: context.colors.error),
              label: Text('Delete group', style: TextStyle(color: context.colors.error)),
            )
          else
            TextButton.icon(
              onPressed: () => _leaveOrDelete(g),
              icon: const Icon(Icons.logout),
              label: const Text('Leave group'),
            ),
        ],
      );
    },
  );

  Future<void> _addMember(Group g) async {
    try {
      final overview = await deps.social.friends();
      if (!mounted) return;
      final memberIds = {for (final m in g.members) m.user.id};
      final candidates = overview.friends.where((f) => !memberIds.contains(f.id)).toList();
      if (candidates.isEmpty) {
        showDone(context, 'All your friends are already here. Add friends first to invite them.');
        return;
      }
      final picked = await showModalBottomSheet<PublicUser>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in candidates)
                ListTile(
                  title: Text(f.displayName),
                  subtitle: Text(f.handle),
                  onTap: () => Navigator.pop(sheet, f),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      await _run(() => deps.social.addMember(g.id, picked.id), group);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _leaveOrDelete(Group g) async {
    final myId = AuthScope.read(context).user?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(g.isOwner ? 'Delete this group?' : 'Leave this group?'),
        content: Text(g.isOwner ? 'The chat, posts and challenges go with it.' : 'You can be added again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true || myId == null) return;
    try {
      if (g.isOwner) {
        await deps.social.deleteGroup(g.id);
      } else {
        await deps.social.removeMember(g.id, myId);
      }
      _poll?.cancel();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _ChallengeInput {
  const _ChallengeInput(this.title, this.metric, this.target, this.start, this.end);
  final String title;
  final ChallengeMetric metric;
  final int target;
  final DateTime start, end;
}

class _ChallengeDialog extends StatefulWidget {
  const _ChallengeDialog();
  @override
  State<_ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<_ChallengeDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _target = TextEditingController(text: '20');
  var _metric = ChallengeMetric.studySessions;
  var _days = 7;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New challenge'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. 20 sessions this week'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Give it a name' : null,
            ),
            DropdownButtonFormField<ChallengeMetric>(
              initialValue: _metric,
              decoration: const InputDecoration(labelText: 'Measure'),
              items: [
                for (final m in ChallengeMetric.values)
                  DropdownMenuItem(value: m, child: Text(challengeMetricLabel[m]!)),
              ],
              onChanged: (v) => setState(() => _metric = v ?? _metric),
            ),
            TextFormField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Target per person'),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n < 1 ? 'Enter a number above 0' : null;
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: const InputDecoration(labelText: 'Length'),
              items: const [
                DropdownMenuItem(value: 7, child: Text('1 week')),
                DropdownMenuItem(value: 14, child: Text('2 weeks')),
                DropdownMenuItem(value: 30, child: Text('30 days')),
              ],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          final start = DateUtils.dateOnly(DateTime.now());
          Navigator.pop(
            context,
            _ChallengeInput(
              _title.text.trim(),
              _metric,
              int.parse(_target.text.trim()),
              start,
              start.add(Duration(days: _days - 1)),
            ),
          );
        },
        child: const Text('Start'),
      ),
    ],
  );
}
