import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/assistant/assistant_controller.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';

/// Ask Omnia: questions about the user's day, answered from their OMNIA data.
/// Read-only; the conversation belongs to the session's [AssistantController].
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  /// Full screen above the tab bar, like the app's other editors.
  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => const AssistantPage()));

  static const suggestions = [
    'What should I prioritize tonight?',
    'What exams do I have coming up?',
    'What tasks are most urgent?',
    'How am I doing today?',
    'Should I study or work out first?',
  ];

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(AssistantController controller, String text) {
    if (controller.sending || text.trim().isEmpty) return;
    _input.clear();
    controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    final sample = AppDependenciesScope.of(context).sampleContent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask Omnia'),
        actions: [
          if (sample)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: LabelTag(text: 'SAMPLE')),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: controller.isEmpty
                  ? _Intro(
                      sample: sample,
                      onAsk: (text) => _send(controller, text),
                    )
                  : _Conversation(controller: controller),
            ),
            _Composer(
              input: _input,
              sending: controller.sending,
              onSend: (text) => _send(controller, text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.sample, required this.onAsk});
  final bool sample;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      HardCard(
        color: lilac,
        prominent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const OmniaMark(),
                const SizedBox(width: 9),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: const Text(
                      'Ask about your day',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              sample
                  ? 'These are sample answers about the demo day. Sign in to '
                        'ask about your own tasks, exams, study, activity and '
                        'sleep.'
                  : 'Omnia answers from your tasks, exams, study, activity '
                        "and sleep in OMNIA. It can't change anything for you.",
              style: const TextStyle(height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Try asking'),
      for (final question in AssistantPage.suggestions) ...[
        Semantics(
          button: true,
          child: HardCard(
            color: paper,
            shadowOffset: const Offset(2, 3),
            onTap: () => onAsk(question),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.north_east_rounded, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );
}

/// Newest at the bottom: the list is reversed so it stays scrolled there.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.controller});
  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final messages = controller.messages;
    final pending = controller.pending;
    final items = <Widget>[
      for (final (i, message) in messages.indexed)
        _Bubble(message, announce: i == messages.length - 1),
      if (pending != null) _Bubble(AssistantMessage.user(pending)),
      if (controller.sending) const _Thinking(),
      if (!controller.sending && controller.error != null)
        _FailureCard(controller: controller),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(18),
      children: items.reversed.toList(),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message, {this.announce = false});
  final AssistantMessage message;

  /// The newest reply is read out by screen readers when it arrives.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .84,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HardCard(
            color: user ? blue : paper,
            shadowOffset: const Offset(2, 3),
            // One node per turn ("OMNIA", then the text), so the flag that
            // announces a new reply sits on the node a screen reader reads.
            child: MergeSemantics(
              child: Semantics(
                liveRegion: announce && !user,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user ? 'YOU' : 'OMNIA', style: OmniaText.label),
                    const SizedBox(height: 4),
                    Text(message.text, style: const TextStyle(height: 1.35)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: HardCard(
          color: paper,
          shadowOffset: const Offset(2, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: context.foreground,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(child: Text('Omnia is thinking…')),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.controller});
  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final title = switch (controller.failure) {
      AssistantFailure.unavailable => "Omnia's assistant is unavailable",
      AssistantFailure.network => 'No answer from OMNIA',
      _ => "Omnia couldn't answer",
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: HardCard(
          color: yellow,
          shadowOffset: const Offset(2, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(friendlyError(controller.error!)),
              const SizedBox(height: 12),
              SolidAction(label: 'Try again', onTap: controller.retry),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController input;
  final bool sending;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.navigationSurface,
      border: Border(top: BorderSide(color: context.outline, width: 1.5)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: input,
              enabled: !sending,
              minLines: 1,
              maxLines: 4,
              maxLength: AssistantRepository.maxMessageLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              decoration: const InputDecoration(
                hintText: 'Ask Omnia about your day',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: input,
            builder: (context, value, _) => IconButton.filled(
              tooltip: 'Send',
              onPressed: sending || value.text.trim().isEmpty
                  ? null
                  : () => onSend(value.text),
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: context.actionBackground,
                foregroundColor: context.actionForeground,
                minimumSize: const Size.square(48),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
