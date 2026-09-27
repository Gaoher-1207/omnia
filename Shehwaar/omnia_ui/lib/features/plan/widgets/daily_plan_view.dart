import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';

/// Real server suggestions. Informational items stay static; only actions press.
class DailyPlanView extends StatefulWidget {
  const DailyPlanView({super.key, this.today});
  final DateTime? today;
  @override
  State<DailyPlanView> createState() => _DailyPlanViewState();
}

class _DailyPlanViewState extends State<DailyPlanView> {
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final controller = PlanScope.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.loaded) controller.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlanScope.of(context);
    final plan = controller.plan;
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Semantics(
            header: true,
            child: const Text(
              "Today's Plan",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 16),
          if (plan == null && widget.today != null)
            Text(formatLongDate(widget.today!), textAlign: TextAlign.center),
          if (controller.busy ||
              (!controller.loaded && controller.error == null))
            const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Loading plan'),
            ),
          if (controller.error != null)
            ErrorView(
              title: "Couldn't refresh your plan",
              error: controller.error!,
              onRetry: controller.load,
            ),
          if (plan == null &&
              controller.loaded &&
              !controller.busy &&
              controller.error == null)
            const EmptyCard(
              title: 'No plan yet.',
              detail: 'Create a suggestion from your tasks, study, sleep and activity.',
            ),
          if (plan != null) ...[
            Text(formatLongDate(plan.date), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            HardCard(
              color: lilac,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SUGGESTED PLAN',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(plan.summary),
                  const SizedBox(height: 8),
                  Text(
                    plan.isFallback
                        ? 'Rules fallback · AI could not supply a valid plan.'
                        : plan.source == 'rules'
                        ? 'Built with planning rules.'
                        : 'AI-assisted suggestion.',
                  ),
                  const Text(
                    'Not accepted or automatically updated. No tasks have been changed.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (plan.validationVersion == 0)
              const Text(
                'Older suggestion: generated before the current deadline and reference checks. Generate a new suggestion.',
              ),
            if (plan.windowStart != null)
              Text(
                'Planning window: ${plan.windowStart}–${plan.windowEnd} · profile time zone',
              ),
            for (final assumption in plan.assumptions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(assumption),
              ),
            const SizedBox(height: 18),
            if (plan.items.isEmpty)
              const EmptyCard(
                title: 'Nothing scheduled.',
                detail: 'Check the remaining work below or try again when more time is available.',
              ),
            for (final item in plan.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HardCard(
                  color: switch (item.category) {
                    'study' => blue,
                    'task' => yellow,
                    'fitness' => mint,
                    _ => lilac,
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.start}–${item.end} · ${item.minutes} min'),
                      Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (item.detail != null) Text(item.detail!),
                    ],
                  ),
                ),
              ),
            if (plan.unscheduled.isNotEmpty) ...[
              const SectionHeader(
                'Not scheduled',
                detail: 'Remaining work, not completed or silently discarded.',
              ),
              for (final work in plan.unscheduled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: HardCard(
                    color: paper,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          work.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${work.remainingMinutes} min remaining · ${work.reason == 'deadline_passed' ? 'Deadline already passed' : 'Not allocated in this suggestion'}',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (plan.adjustments.isNotEmpty) ...[
              const SectionHeader(
                'Planning notes',
                detail: 'Reasons for this suggestion, not a comparison with your previous plan.',
              ),
              for (final note in plan.adjustments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(note),
                ),
            ],
            for (final tip in plan.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tip),
              ),
          ],
          const SizedBox(height: 18),
          if (!controller.busy)
            SolidAction(
              label: plan == null
                  ? 'Generate suggestion'
                  : 'Generate new suggestion',
              onTap: controller.generate,
            ),
          const SizedBox(height: 24),
          const SectionHeader(
            'Focus',
            detail: 'Timed work blocks with breaks.',
          ),
          const FocusTimerEntry(),
        ],
      ),
    );
  }
}
