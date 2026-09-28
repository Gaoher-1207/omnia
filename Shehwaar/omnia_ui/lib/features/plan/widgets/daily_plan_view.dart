import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_preferences_page.dart';
import 'package:omnia_ui/features/plan/plan_time.dart';
import 'package:omnia_ui/features/plan/widgets/plan_date_strip.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/tasks/task_form_page.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/subject_detail_page.dart';

class DailyPlanView extends StatefulWidget {
  const DailyPlanView({super.key, this.today});
  final DateTime? today;
  @override
  State<DailyPlanView> createState() => _DailyPlanViewState();
}

class _DailyPlanViewState extends State<DailyPlanView> {
  bool _started = false;
  DateTime? _requestedAvailabilityDate;
  bool _requestedAvailability = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final controller = PlanScope.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.loaded && !controller.loadsWithDashboard) {
          controller.load();
        }
      });
    }
  }

  Future<void> _openTask(DailyPlanItem item) async {
    final controller = PlanScope.of(context);
    final tasks = TaskScope.of(context);
    try {
      // Fetch the current owned entity, not a copy assembled from the snapshot.
      final task = await AppDependenciesScope.of(context).tasks
          .getTask(item.taskId!);
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => TaskFormPage(
            initial: task,
            onSave: (edited) async {
              final saved = await tasks.update(edited);
              if (saved) controller.markEdited();
              return saved;
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This task could not be opened. It may have been removed. Try refreshing.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openSubject(String id) async {
    final study = StudyScope.read(context);
    await study.load();
    if (!mounted) return;
    if (!study.subjects.any((s) => s.id == id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This subject is unavailable.')),
      );
      return;
    }
    SubjectDetailPage.open(context, id);
  }

  void _details(DailyPlan plan, String format) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      builder: (context, scroll) =>
          _PlanExplanationSheet(plan: plan, format: format, scroll: scroll),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = PlanScope.of(context);
    final plan = controller.plan;
    final profile = AuthScope.maybeOf(context)?.user?.profile;
    final format = profile?.timeFormat ?? '24h';
    // Today comes from the server dashboard. A persisted date is only a fallback
    // for rendering; it does not redefine Today after navigating history.
    final today = widget.today;
    final selected = controller.selectedDate ?? today ?? plan?.date;
    final commitments = CommitmentScope.maybeOf(context);
    final availabilityDate = controller.selectedDate ?? today;
    if (commitments != null &&
        availabilityDate != null &&
        (!_requestedAvailability ||
            !DateUtils.isSameDay(
              _requestedAvailabilityDate,
              availabilityDate,
            ))) {
      _requestedAvailability = true;
      _requestedAvailabilityDate = availabilityDate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) commitments.loadForDate(_requestedAvailabilityDate);
      });
    }
    final availability = commitments?.availability;
    final applicable =
        availability != null &&
            selected != null &&
            DateUtils.isSameDay(availability.day, selected)
        ? availability.commitments
        : <Commitment>[];
    final timeline = <({int start, DailyPlanItem? item, Commitment? fixed})>[
      if (plan != null)
        for (final item in plan.items)
          (start: DailyPlanItem.minutesOf(item.start), item: item, fixed: null),
      for (final fixed in applicable)
        (start: fixed.startMinutes, item: null, fixed: fixed),
    ]..sort((left, right) => left.start.compareTo(right.start));
    final isToday =
        controller.selectedDate == null ||
        (today != null && DateUtils.isSameDay(selected, today));
    final changedHours =
        plan != null &&
        profile != null &&
        plan.planningStartMinutes != null &&
        (plan.planningStartMinutes != profile.planningStartMinutes ||
            plan.planningEndMinutes != profile.planningEndMinutes);
    final overlapsCurrentCommitment =
        plan != null &&
        plan.items.any(
          (item) => applicable.any(
            (fixed) =>
                DailyPlanItem.minutesOf(item.start) < fixed.endMinutes &&
                DailyPlanItem.minutesOf(item.end) > fixed.startMinutes,
          ),
        );
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    isToday ? "Today's Plan" : 'Day Plan',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (profile != null)
                IconButton(
                  tooltip: 'Plan preferences',
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PlanPreferencesPage(),
                    ),
                  ),
                ),
            ],
          ),
          if (selected != null) Text(formatLongDate(selected)),
          if (today != null && selected != null)
            PlanDateStrip(
              today: today,
              selected: selected,
              onSelect: controller.selectDate,
            ),
          const SizedBox(height: 10),
          if (commitments?.error != null)
            TextButton(
              onPressed: () => commitments!.loadForDate(
                controller.selectedDate ?? today,
                force: true,
              ),
              child: const Text('Could not load fixed commitments. Retry'),
            ),
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
            EmptyCard(
              title: 'No plan for this date.',
              detail: isToday
                  ? 'Generate a suggestion from your Omnia data.'
                  : 'No persisted suggestion. Return to Today to generate one.',
            ),
          if (availability != null && availability.freeIntervals.isEmpty)
            const EmptyCard(
              title: 'No free planning time.',
              detail: 'Fixed commitments fill the saved planning hours for this date.',
            ),
          if (plan != null) ...[
            if (selected != null && !DateUtils.isSameDay(plan.date, selected))
              Text(
                'Showing the saved suggestion for ${formatLongDate(plan.date)}.',
              ),
            HardCard(
              color: lilac,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      Text(
                        plan.isFallback
                            ? 'RULES FALLBACK'
                            : plan.source == 'rules'
                            ? 'RULES PLAN'
                            : 'OMNIAI PLAN',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      TextButton(
                        onPressed: () => _details(plan, format),
                        child: const Text('Why?'),
                      ),
                    ],
                  ),
                  Text(
                    plan.explanation?.headline ?? plan.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (changedHours ||
                overlapsCurrentCommitment ||
                controller.mayBeStale)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  changedHours
                      ? 'Planning hours changed. This snapshot keeps its original times; regenerate to use the new hours.'
                      : overlapsCurrentCommitment
                      ? 'A fixed commitment overlaps this saved suggestion. Its times are unchanged; regenerate to use current availability.'
                      : 'A task or commitment changed. This snapshot is unchanged; regenerate to use current facts.',
                ),
              ),
            const SizedBox(height: 18),
            if (plan.items.isEmpty && applicable.isEmpty)
              const EmptyCard(
                title: 'Nothing scheduled.',
                detail: 'Review remaining work below.',
              ),
          ],
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final entry in timeline)
              if (entry.item != null)
                _timelineItem(entry.item!, format)
              else
                _commitmentItem(entry.fixed!, format),
          ],
          if (plan != null) ...[
            if (plan.unscheduled.isNotEmpty) ...[
              const SectionHeader(
                'Not scheduled',
                detail: 'Remaining work, not completed.',
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
                          '${work.remainingMinutes} min remaining · ${work.reason == 'deadline_passed' ? 'Deadline already passed' : 'Not allocated'}',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 16),
          if (!controller.busy && isToday)
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

  Widget _timelineItem(DailyPlanItem item, String format) {
    final start = formatPlanTime(item.start, format),
        end = formatPlanTime(item.end, format);
    final VoidCallback? action = item.taskId != null
        ? () => _openTask(item)
        : item.subjectId != null
        ? () => _openSubject(item.subjectId!)
        : null;
    final destination = item.taskId != null
        ? 'Open task'
        : item.subjectId != null
        ? 'Open subject'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(38).clamp(64, 88),
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 8),
                child: Text(
                  start,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Container(width: 2, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                button: action != null,
                label:
                    '${item.title}, $start to $end. ${item.detail ?? ''}. $destination',
                child: HardCard(
                  color: switch (item.category) {
                    'task' => yellow,
                    'study' => blue,
                    'fitness' => mint,
                    _ => lilac,
                  },
                  onTap: action,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (item.minutes * 1.2).clamp(42, 144),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text('$start–$end · ${item.minutes} min'),
                        if (item.detail != null) Text(item.detail!),
                        if (action != null)
                          Text(
                            destination,
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commitmentItem(Commitment fixed, String format) {
    final start = formatPlanMinutes(fixed.startMinutes, format);
    final end = formatPlanMinutes(fixed.endMinutes, format);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(38).clamp(64, 88),
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 8),
                child: Text(
                  start,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Container(width: 2, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                label: '${fixed.title}, $start to $end. Fixed commitment.',
                child: HardCard(
                  color: paper,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FIXED COMMITMENT',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        fixed.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('$start–$end'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanExplanationSheet extends StatefulWidget {
  const _PlanExplanationSheet({
    required this.plan,
    required this.format,
    required this.scroll,
  });

  final DailyPlan plan;
  final String format;
  final ScrollController scroll;

  @override
  State<_PlanExplanationSheet> createState() => _PlanExplanationSheetState();
}

class _PlanExplanationSheetState extends State<_PlanExplanationSheet> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final explanation = plan.displayExplanation;
    final source = plan.isFallback
        ? 'Rules fallback'
        : plan.source == 'rules'
        ? 'Rules plan'
        : 'OmniAI plan';
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Why this plan?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          explanation.headline,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        if (explanation.keyReasons.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            "Today's priorities",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          for (final reason in explanation.keyReasons.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(reason)),
                ],
              ),
            ),
        ],
        if (explanation.supportingContext.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Also considered',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final fact in explanation.supportingContext.take(2))
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(fact)),
        ],
        const SizedBox(height: 16),
        Text(source, style: const TextStyle(fontWeight: FontWeight.w800)),
        TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          child: Text(expanded ? 'Hide details' : 'Show details'),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Text(plan.summary),
          const SizedBox(height: 10),
          Text(
            plan.isFallback
                ? 'Rules fallback: OmniAI could not supply a valid plan.'
                : plan.source == 'rules'
                ? 'Built with planning rules.'
                : 'Planned with OmniAI.',
          ),
          const Text(
            'Suggested, not accepted or automatically updated. Generating this suggestion changed no tasks.',
          ),
          if (plan.validationVersion == 0)
            const Text(
              'Older suggestion: generated before current deadline and reference checks.',
            ),
          if (plan.windowStart != null && plan.windowEnd != null)
            Text(
              'Planning window: ${formatPlanTime(plan.windowStart!, widget.format)}–${formatPlanTime(plan.windowEnd!, widget.format)} · profile time zone',
            ),
          for (final fact in explanation.supportingContext.skip(2))
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(fact)),
          for (final text in [
            ...plan.assumptions,
            ...plan.adjustments,
            ...plan.tips,
          ])
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(text)),
        ],
      ],
    );
  }
}
