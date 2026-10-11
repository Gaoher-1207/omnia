import 'package:flutter/material.dart';
import 'package:omnia_ui/features/assistant/widgets/ask_omnia_button.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/number_wheel.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/plan/add_plan_item_page.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/commitment.dart';
import 'package:omnia_ui/features/plan/commitment_controller.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_preferences_page.dart';
import 'package:omnia_ui/features/plan/plan_time.dart';
import 'package:omnia_ui/features/plan/widgets/replan_preview.dart';
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

  /// Ask for a request, then show a preview. Nothing changes until Apply.
  Future<void> _adjustPlan(PlanController controller) async {
    final request = await showDialog<String>(
      context: context,
      builder: (_) => const _ReplanRequestDialog(),
    );
    if (!mounted || request == null) return;
    await previewReplan(context, controller, request);
  }

  void _details(DailyPlan plan, String format) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: _PlanExplanationSheet(plan: plan, format: format),
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
    // Mock mode keeps blocks added by hand but has no planner to call.
    final canPlan =
        !(AppDependenciesScope.maybeOf(context)?.sampleContent ?? false);
    final canAdd =
        today != null &&
        selected != null &&
        !DateUtils.dateOnly(selected).isBefore(DateUtils.dateOnly(today));
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
        // The last item can scroll clear of the floating Ask OmniAI button.
        padding: EdgeInsets.fromLTRB(18, 18, 18, askOmniaClearance(context)),
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
          if (canAdd) AddToPlanButton(day: selected, today: today),
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
              detail: !canPlan
                  ? 'Add a block to plan this day.'
                  : isToday
                  ? 'Generate a suggestion from your Omnia data.'
                  : canAdd
                  ? 'Add a block to plan this day, or return to Today to generate a suggestion.'
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
                        plan.source == 'manual'
                            ? 'Your plan'
                            : 'Suggested plan',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      TextButton(
                        onPressed: () => _details(plan, format),
                        child: const Text('Why?'),
                      ),
                    ],
                  ),
                  Text(
                    plan.source == 'manual'
                        ? 'Added by you'
                        : plan.isFallback
                        ? 'Rules fallback'
                        : plan.source == 'rules'
                        ? 'Planned with rules'
                        : 'OmniAI assisted',
                    style: OmniaText.meta,
                  ),
                  const SizedBox(height: 5),
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
                _timelineItem(
                  entry.item!,
                  format,
                  canRecord:
                      plan != null &&
                      today != null &&
                      !DateUtils.dateOnly(plan.date).isAfter(today),
                  // History stays as it was; today and later can change.
                  removeFrom:
                      plan != null &&
                          today != null &&
                          !DateUtils.dateOnly(plan.date)
                              .isBefore(DateUtils.dateOnly(today))
                      ? plan
                      : null,
                )
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
          if (!controller.busy && isToday && canPlan)
            SolidAction(
              label: plan == null
                  ? 'Generate suggestion'
                  : 'Generate new suggestion',
              onTap: controller.generate,
            ),
          if (!controller.busy &&
              isToday &&
              canPlan &&
              plan != null &&
              (selected == null ||
                  DateUtils.isSameDay(plan.date, selected))) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.creatingProposal
                    ? null
                    : () => _adjustPlan(controller),
                icon: controller.creatingProposal
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Preparing changes',
                        ),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(
                  controller.creatingProposal
                      ? 'Preparing changes…'
                      : 'Adjust today’s plan',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.foreground,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: BorderSide(color: context.outline, width: 1.5),
                ),
              ),
            ),
          ],
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

  Future<void> _recordOutcome(DailyPlanItem item, String? status) async {
    final controller = PlanScope.of(context);
    final tasks = TaskScope.of(context);
    int? minutes;
    // A study block partly done counts only the minutes actually studied.
    if (status == 'partial' && item.category == 'study' && item.minutes > 1) {
      final picked = await showDialog<int>(
        context: context,
        builder: (_) => _PartialMinutesDialog(item: item),
      );
      if (!mounted || picked == null) return;
      minutes = picked;
    }
    final saved = await controller.recordOutcome(
      item,
      status,
      minutes: minutes,
    );
    if (!mounted) return;
    if (saved) {
      // Task outcomes update the canonical task record on the backend. The
      // Tasks tab keeps an app-session snapshot, so reload it after completion.
      if (item.category == 'task' && status == 'done') {
        await tasks.load();
        if (!mounted) return;
      }
      // Study check-offs change today's study minutes.
      if (item.category == 'study') {
        context
            .getInheritedWidgetOfExactType<DashboardScope>()
            ?.notifier
            ?.load();
      }
      return;
    }
    final failure = controller.outcomeError;
    if (failure == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure is ApiException && failure.code == 'plan_item_stale'
              ? 'Your plan changed, so it was refreshed. Try again.'
              : friendlyError(failure),
        ),
      ),
    );
  }

  Widget _timelineItem(
    DailyPlanItem item,
    String format, {
    bool canRecord = false,
    DailyPlan? removeFrom,
  }) {
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
                    '${item.title}, $start to $end. ${item.detail ?? ''}. '
                    '${item.outcome == null ? '' : '${_outcomeText(item)}. '}'
                    '$destination',
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '$start–$end · ${item.minutes} min'
                                '${item.manual ? ' · Added by you' : ''}',
                              ),
                              if (item.detail != null) Text(item.detail!),
                              if (item.outcome != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _outcomeText(item).toUpperCase(),
                                    style: OmniaText.label,
                                  ),
                                ),
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
                        if ((canRecord || removeFrom != null) &&
                            item.itemKey != null) ...[
                          const SizedBox(width: 10),
                          _OutcomeButton(
                            item: item,
                            busy:
                                PlanScope.of(context)
                                    .outcomeBusy(item.itemKey!) ||
                                PlanScope.of(context).removing(item.itemKey!),
                            onSelected: canRecord
                                ? (status) => _recordOutcome(item, status)
                                : null,
                            onRemove: removeFrom == null
                                ? null
                                : () =>
                                      _confirmRemove(removeFrom, item, format),
                          ),
                        ],
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

  /// Press and hold a block's status square: say which block, then ask once
  /// more before removing it. Cancel at either step changes nothing.
  Future<void> _confirmRemove(
    DailyPlan plan,
    DailyPlanItem item,
    String format,
  ) async {
    final controller = PlanScope.of(context);
    final when =
        '${formatPlanTime(item.start, format)}–'
        '${formatPlanTime(item.end, format)} · ${formatLongDate(plan.date)}';
    final wantsRemove = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _RemoveSheet(item: item, when: when),
    );
    if (wantsRemove != true || !mounted) return;
    final kept = item.taskId != null
        ? 'The task stays in Tasks.'
        : item.subjectId != null
        ? 'The subject and any study time already logged stay.'
        : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${item.title}”?'),
        content: Text(
          'It comes off this day’s plan ($when). '
          'Nothing else in the plan changes.${kept == null ? '' : ' $kept'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final removed = await controller.removeItem(plan, item);
    if (!mounted) return;
    final failure = controller.removeError;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? 'Removed ${item.title} from your plan.'
              : failure is ApiException &&
                    (failure.code == 'plan_stale' ||
                        failure.code == 'plan_item_stale')
              ? 'Your plan changed, so it was refreshed. Nothing was removed.'
              : friendlyError(failure ?? StateError('failed')),
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

/// Opens the hand-added block form for [day]. The same full-width outline
/// style as "Adjust today's plan".
class AddToPlanButton extends StatelessWidget {
  const AddToPlanButton({super.key, required this.day, required this.today});
  final DateTime day, today;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => AddPlanItemPage.open(context, day: day, today: today),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add to plan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.foreground,
          padding: const EdgeInsets.symmetric(vertical: 15),
          side: BorderSide(color: context.outline, width: 1.5),
        ),
      ),
    ),
  );
}

class _ReplanRequestDialog extends StatefulWidget {
  const _ReplanRequestDialog();
  @override
  State<_ReplanRequestDialog> createState() => _ReplanRequestDialogState();
}

class _ReplanRequestDialogState extends State<_ReplanRequestDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adjust today’s plan'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        maxLength: 1000,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'What would you like to change?',
          hintText: 'For example, move study earlier this afternoon.',
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Describe the change you want'
            : null,
        onFieldSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Preview changes')),
    ],
  );
}

class _PlanExplanationSheet extends StatefulWidget {
  const _PlanExplanationSheet({required this.plan, required this.format});

  final DailyPlan plan;
  final String format;

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
      shrinkWrap: true,
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

String _outcomeLabel(String outcome) => switch (outcome) {
  'done' => 'Done',
  'partial' => 'Partly done',
  'skipped' => 'Not done',
  _ => outcome,
};

/// "Partly done · 20 min" when the minutes are known.
String _outcomeText(DailyPlanItem item) {
  final label = _outcomeLabel(item.outcome!);
  final minutes = item.outcomeMinutes;
  return item.outcome == 'partial' && minutes != null
      ? '$label · $minutes min'
      : label;
}

/// The check-off square inside a block: neutral until something is recorded,
/// then green ✓ (done), yellow – (partly done) or red × (not done). Opens a
/// menu to choose or clear. Its own semantics node, so the block itself stays
/// one control (open task/subject) for screen readers.
class _OutcomeButton extends StatelessWidget {
  const _OutcomeButton({
    required this.item,
    required this.busy,
    required this.onSelected,
    this.onRemove,
  });
  final DailyPlanItem item;
  final bool busy;

  /// Null on a later day: outcomes are recorded on the day.
  final ValueChanged<String?>? onSelected;

  /// Press and hold; null where blocks can't be removed (past days).
  final VoidCallback? onRemove;

  static const _clear = 'clear';

  @override
  Widget build(BuildContext context) {
    final outcome = item.outcome;
    final fill = switch (outcome) {
      'done' => outcomeDone,
      'partial' => outcomePartial,
      'skipped' => outcomeNotDone,
      _ => null,
    };
    final record = onSelected;
    final remove = busy ? null : onRemove;
    final label = record == null
        ? '${item.title}: checked off on the day'
        : outcome == null
        ? 'Not checked off: ${item.title}. Record what happened'
        : '${_outcomeText(item)}: ${item.title}. Change';
    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      label: label,
      hint: remove == null ? null : 'Hold to remove from plan',
      excludeSemantics: true,
      onTap: busy ? null : () {},
      onLongPress: remove,
      child: GestureDetector(
        // Only a deliberate hold offers removal; a tap never does.
        onLongPress: remove,
        // The menu's tooltip would otherwise claim the hold on touch screens;
        // it still shows on hover, and the label above is what is announced.
        child: TooltipTheme(
          data: TooltipTheme.of(context)
              .copyWith(triggerMode: TooltipTriggerMode.manual),
          child: PopupMenuButton<String>(
            enabled: !busy,
            tooltip: label,
            onSelected: (value) => record?.call(value == _clear ? null : value),
            itemBuilder: (context) => [
              if (record == null)
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('You can check this off on the day.'),
                )
              else ...[
                for (final status in const ['done', 'partial', 'skipped'])
                  CheckedPopupMenuItem<String>(
                    value: status,
                    checked: outcome == status,
                    child: Text(_outcomeLabel(status)),
                  ),
                if (outcome != null)
                  const PopupMenuItem<String>(
                    value: _clear,
                    child: Text('Clear'),
                  ),
              ],
              if (remove != null) ...[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('Hold the square to remove this block'),
                ),
              ],
            ],
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                // Cards stay pastel in both themes, so ink reads on every state;
                // the unchecked square is a light, unfilled box.
                color: fill ?? Colors.white.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ink, width: 2),
                boxShadow: fill == null
                    ? null
                    : const [BoxShadow(color: ink, offset: Offset(2, 2))],
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: ink,
                      ),
                    )
                  : outcome == null
                  ? null
                  : CustomPaint(painter: _OutcomeMark(outcome)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first step of removing a block: names exactly which one.
class _RemoveSheet extends StatelessWidget {
  const _RemoveSheet({required this.item, required this.when});
  final DailyPlanItem item;
  final String when;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              item.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          Text(when),
          if (item.manual) const Text('Added by you'),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove from plan…'),
            style: OutlinedButton.styleFrom(
              foregroundColor: error,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: error, width: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Bold ✓, – and × drawn in ink, so they read on every fill in both themes.
class _OutcomeMark extends CustomPainter {
  const _OutcomeMark(this.outcome);
  final String outcome;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink
      ..strokeWidth = size.width * .11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    final path = Path();
    switch (outcome) {
      case 'done':
        path
          ..moveTo(w * .26, h * .52)
          ..lineTo(w * .43, h * .68)
          ..lineTo(w * .75, h * .33);
      case 'partial':
        path
          ..moveTo(w * .28, h * .5)
          ..lineTo(w * .72, h * .5);
      default:
        path
          ..moveTo(w * .31, h * .31)
          ..lineTo(w * .69, h * .69)
          ..moveTo(w * .69, h * .31)
          ..lineTo(w * .31, h * .69);
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_OutcomeMark old) => old.outcome != outcome;
}

/// "How long did you study?" for a study block that was partly done: only
/// these minutes count as study time, never the whole block.
class _PartialMinutesDialog extends StatefulWidget {
  const _PartialMinutesDialog({required this.item});
  final DailyPlanItem item;

  @override
  State<_PartialMinutesDialog> createState() => _PartialMinutesDialogState();
}

class _PartialMinutesDialogState extends State<_PartialMinutesDialog> {
  late final List<int> options = [
    if (widget.item.minutes >= 10)
      for (var m = 5; m < widget.item.minutes; m += 5) m
    else
      for (var m = 1; m < widget.item.minutes; m++) m,
  ];
  late int minutes = options[(options.length - 1) ~/ 2];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('How long did you study?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Only these minutes count as study for "${widget.item.title}".'),
        const SizedBox(height: 16),
        NumberWheel(
          label: 'Minutes studied',
          values: options,
          value: minutes,
          format: (value) => '$value min',
          width: 120,
          onChanged: (value) => setState(() => minutes = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, minutes),
        child: Text('Save $minutes min'),
      ),
    ],
  );
}
