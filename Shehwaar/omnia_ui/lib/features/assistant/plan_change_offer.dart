import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/action_row.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/widgets/replan_preview.dart';

final _changeWords = RegExp(
  r'\b(move|moving|reschedule|push|postpone|delay|skip|cancel|drop|remove|'
  r'shorten|swap|switch|replan|rearrange|reorder|fit in|add|squeeze|earlier|'
  r'later|instead|free up|clear)\b',
  caseSensitive: false,
);
final _planWords = RegExp(
  r"\b(plan|schedule|today|tonight|this (morning|afternoon|evening)|"
  r'block|session|workout|gym|study|revision|task|assignment|break|'
  r'\d{1,2}(:\d{2})?\s*(am|pm)?)\b',
  caseSensitive: false,
);

/// Whether [text] reads like a request to change today's plan, such as
/// "Move my workout to 7 pm" or "Skip the gym today". Questions about the
/// plan ("What should I do first?") are not.
bool looksLikePlanChange(String text) =>
    _changeWords.hasMatch(text) && _planWords.hasMatch(text);

/// Offered under Ask Omnia's latest reply when the user asked to change the
/// plan. It runs the same validated replan flow as Plan's "Adjust today's
/// plan": a preview first, and nothing changes until the user taps Apply.
/// Ask Omnia itself still never changes anything.
class PlanChangeOffer extends StatelessWidget {
  const PlanChangeOffer({super.key, required this.request});
  final String request;

  /// The request to offer, if the conversation ends with one. Only in a
  /// signed-in session that has today's plan to change.
  static String? requestFor(
    BuildContext context,
    List<AssistantMessage> messages,
  ) {
    if (AppDependenciesScope.of(context).sampleContent) return null;
    final plan = PlanScope.maybeOf(context);
    if (plan == null || plan.todayPlan == null) return null;
    if (messages.length < 2 || messages.last.fromUser) return null;
    final asked = messages[messages.length - 2];
    return asked.fromUser && looksLikePlanChange(asked.text)
        ? asked.text
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final plan = PlanScope.of(context);
    final busy = plan.creatingProposal || plan.proposalActionBusy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HardCard(
        color: lilac,
        shadowOffset: const Offset(2, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Want to change today’s plan?',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'See the exact changes first. Nothing changes unless you apply them.',
              style: TextStyle(color: context.cardForeground(lilac)),
            ),
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Preparing plan changes',
              )
            else
              OutlineAction(
                icon: Icons.auto_awesome_outlined,
                label: 'Preview plan change',
                onPressed: () => previewReplan(context, plan, request),
              ),
          ],
        ),
      ),
    );
  }
}
