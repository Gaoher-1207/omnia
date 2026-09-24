import 'package:flutter/material.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
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

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Center(
        child: Semantics(
          header: true,
          child: Text(
            "Today's Plan",
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text(
          'Tue, Sep 23  ·  SAMPLE DAY',
          style: TextStyle(color: context.mutedForeground, fontSize: 12),
        ),
      ),
      const SizedBox(height: 22),
      Container(
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
      ),
      const SizedBox(height: 21),
      if (view == PlanView.focus) ...[
        HardCard(
          color: blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                samplePlan[2].displayTitle(context),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text('10:00 · 45m · Sample focus activity'),
              const SizedBox(height: 12),
              SolidAction(
                label: 'Open revision',
                onTap: () => openPlanItem(context, samplePlan[2]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const FocusTimerEntry(),
      ] else
        for (final item in samplePlan)
          TimelineRow(
            time: item.time,
            title: item.displayTitle(context),
            duration: item.duration,
            icon: item.icon,
            color: item.color,
            showTimeline: view == PlanView.timeline,
            showChevron: item.isRevision,
            onTap: () => openPlanItem(context, item),
          ),
      const SizedBox(height: 18),
      HardCard(
        color: lilac,
        prominent: true,
        onTap: () => showInfoDialog(
          context,
          'Adaptive planning',
          'Coming soon. This sample plan does not automatically reschedule activities yet.',
        ),
        child: const Row(
          children: [
            OmniaMark(),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Your plan will adapt as your day changes.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            // Explains itself on tap, but does not navigate anywhere yet.
            LabelTag(text: 'SOON'),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'Timeline is a visual sample. Scheduling and rescheduling '
        'will be connected when the planning API is ready.',
        style: TextStyle(color: context.mutedForeground, fontSize: 12),
      ),
    ],
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
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                name,
                style: TextStyle(
                  color: selected
                      ? context.cardForeground(lilac)
                      : context.mutedForeground,
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
