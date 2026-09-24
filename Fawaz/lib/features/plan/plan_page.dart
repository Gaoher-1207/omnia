import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/plan_item.dart';
import 'package:omnia_ui/features/plan/widgets/timeline_row.dart';

enum PlanView { timeline, list, focus }

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  PlanView view = PlanView.timeline;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate(PlanController controller) async {
    try {
      await controller.generate(note: _note.text);
      _note.clear();
      if (mounted) await SessionScope.refreshDashboard(context);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of<PlanController>(context);
    final dashboard = ControllerScope.of<DashboardState>(context).data;
    final plan = controller.plan;
    final day = plan?.date ?? dashboard?.date;
    final Widget body;
    if (!controller.loaded) {
      body = controller.error == null
          ? const LoadingView()
          : ErrorView(error: controller.error!, onRetry: controller.load, title: "Couldn't load your plan");
    } else if (plan == null) {
      body = _NoPlan(note: _note, busy: controller.generating, onPlan: () => _generate(controller));
    } else {
      body = _PlanBody(
        plan: plan,
        view: view,
        modeSwitch: _modeSwitch(),
        note: _note,
        busy: controller.generating,
        onReplan: () => _generate(controller),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Center(
            child: Text("Today's Plan", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              day == null ? '' : longDate(day),
              style: TextStyle(color: context.mutedForeground, fontSize: 12),
            ),
          ),
          const SizedBox(height: 22),
          body,
        ],
      ),
    );
  }

  Widget _modeSwitch() => Container(
    padding: const EdgeInsets.all(4),
    decoration: SurfaceStyle.of(context).decoration(
      color: context.colors.surfaceContainerHighest,
      radius: 12,
      offset: const Offset(2, 2),
    ),
    child: Row(
      children: [
        _mode('Timeline', PlanView.timeline),
        _mode('List', PlanView.list),
        _mode('Focus', PlanView.focus),
      ],
    ),
  );

  Widget _mode(String name, PlanView option) {
    final selected = view == option;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? context.cardColor(lilac) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => setState(() => view = option),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                name,
                style: TextStyle(
                  color: selected ? context.cardForeground(lilac) : context.mutedForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.note, required this.busy, required this.onPlan});
  final TextEditingController note;
  final bool busy;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => HardCard(
    color: lilac,
    prominent: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            OmniaMark(),
            SizedBox(width: 11),
            Expanded(
              child: Text('No plan for today yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Omnia will schedule the rest of your day from your exams, backlog, '
          'open tasks, activity and sleep.',
          style: TextStyle(height: 1.35),
        ),
        const SizedBox(height: 14),
        _NoteField(controller: note),
        const SizedBox(height: 14),
        SolidAction(label: busy ? 'Planning…' : 'Plan my day', onTap: busy ? () {} : onPlan),
      ],
    ),
  );
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: 280,
    style: TextStyle(color: context.foreground),
    decoration: const InputDecoration(
      labelText: 'Anything I should know? (optional)',
      hintText: 'e.g. slept badly, busy afternoon',
    ),
  );
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({
    required this.plan,
    required this.view,
    required this.modeSwitch,
    required this.note,
    required this.busy,
    required this.onReplan,
  });
  final DailyPlan plan;
  final PlanView view;
  final Widget modeSwitch;
  final TextEditingController note;
  final bool busy;
  final VoidCallback onReplan;

  @override
  Widget build(BuildContext context) {
    final focus = plan.currentOrNext(nowHhmm());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        modeSwitch,
        const SizedBox(height: 21),
        if (plan.items.isEmpty)
          const MessageView(title: 'Nothing left to schedule', detail: 'Rest up. Tomorrow picks up from here.')
        else if (view == PlanView.focus)
          focus == null
              ? const MessageView(title: "You're done for today")
              : HardCard(
                  color: planStyle(focus).color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(focus.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        '${focus.start} · ${formatMinutes(focus.minutes)}'
                        '${focus.detail == null ? '' : ' · ${focus.detail}'}',
                      ),
                      const SizedBox(height: 12),
                      SolidAction(
                        label: focus.category == PlanCategory.study ? 'Open revision' : 'Open',
                        onTap: () => openPlanItem(context, focus),
                      ),
                    ],
                  ),
                )
        else
          for (final item in plan.items)
            TimelineRow(
              time: item.start,
              title: item.title,
              duration: formatMinutes(item.minutes),
              icon: planStyle(item).icon,
              color: planStyle(item).color,
              showTimeline: view == PlanView.timeline,
              showChevron: item.category == PlanCategory.study || item.category == PlanCategory.task,
              onTap: () => openPlanItem(context, item),
            ),
        const SizedBox(height: 18),
        HardCard(
          color: lilac,
          prominent: true,
          onTap: () => _showAdaptive(context),
          child: const Row(
            children: [
              OmniaMark(),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Your plan adapts as your day changes.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.arrow_forward),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${plan.sourceLabel}. ${plan.summary}',
          style: TextStyle(color: context.mutedForeground, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _showAdaptive(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(sheet).bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text('How today was planned', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(plan.sourceLabel, style: TextStyle(color: sheet.mutedForeground)),
          const SizedBox(height: 14),
          if (plan.adjustments.isNotEmpty) ...[
            const Text('What changed and why', style: TextStyle(fontWeight: FontWeight.w900)),
            for (final line in plan.adjustments) _Bullet(line),
            const SizedBox(height: 10),
          ],
          if (plan.tips.isNotEmpty) ...[
            const Text('Tips', style: TextStyle(fontWeight: FontWeight.w900)),
            for (final line in plan.tips) _Bullet(line),
            const SizedBox(height: 10),
          ],
          const Text(
            'Something changed? Tell Omnia and re-plan the rest of the day.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _NoteField(controller: note),
          const SizedBox(height: 8),
          SolidAction(
            label: busy ? 'Planning…' : 'Re-plan my day',
            onTap: () {
              Navigator.pop(sheet);
              onReplan();
            },
          ),
        ],
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}
