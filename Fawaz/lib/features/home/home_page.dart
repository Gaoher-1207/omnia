import 'package:flutter/material.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';
import 'package:omnia_ui/features/plan/plan_item.dart';
import 'package:omnia_ui/features/social/social_page.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/home/widgets/agenda_line.dart';
import 'package:omnia_ui/features/home/widgets/category_card.dart';
import 'package:omnia_ui/features/track/log_pages.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.openPlan, required this.openTrack});
  final VoidCallback openPlan;
  final VoidCallback openTrack;

  @override
  Widget build(BuildContext context) {
    final dashboard = ControllerScope.of<DashboardState>(context);
    final data = dashboard.data;
    if (data == null) {
      return dashboard.error == null
          ? const LoadingView()
          : ErrorView(error: dashboard.error!, onRetry: dashboard.load, title: "Couldn't load your day");
    }
    return RefreshIndicator(
      onRefresh: dashboard.load,
      child: _HomeContent(data: data, openPlan: openPlan, openTrack: openTrack),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.data, required this.openPlan, required this.openTrack});
  final Dashboard data;
  final VoidCallback openPlan, openTrack;

  Future<void> _push(BuildContext context, Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (context.mounted) await SessionScope.refreshDashboard(context);
  }

  @override
  Widget build(BuildContext context) {
    final today = data.today;
    final plan = data.plan;
    final exam = data.nextExam;
    final firstName = data.displayName.trim().split(' ').first;
    return ListView(
      padding: const EdgeInsets.all(18),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Good ${data.greeting},\n$firstName.',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.04,
                  fontWeight: FontWeight.w900,
                  color: context.foreground,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Friends',
              onPressed: () => _push(context, const SocialPage()),
              icon: const Icon(Icons.group_outlined),
              style: IconButton.styleFrom(
                backgroundColor: context.actionBackground,
                foregroundColor: context.actionForeground,
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Settings',
              onPressed: () => _push(context, const SettingsPage()),
              icon: const Icon(Icons.person_outline),
              style: IconButton.styleFrom(
                backgroundColor: context.actionBackground,
                foregroundColor: context.actionForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${longDate(data.date)}  ·  ${data.streaks.balance.current}-DAY BALANCE STREAK',
          style: TextStyle(fontSize: 12, letterSpacing: .4, color: context.foreground),
        ),
        const SizedBox(height: 18),
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
                  const Text('omnia', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  LabelTag(text: plan == null ? 'NO PLAN YET' : (plan.source == 'rules' ? 'PLANNER' : 'AI')),
                ],
              ),
              const SizedBox(height: 17),
              Text(
                exam == null
                    ? 'No exams coming up.'
                    : exam.daysLeft == 0
                    ? 'Your ${exam.subjectName} exam is today.'
                    : 'Your ${exam.subjectName} exam is in ${exam.daysLeft} ${exam.daysLeft == 1 ? 'day' : 'days'}.',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                plan?.summary ??
                    "Get a realistic plan for today built around your exams, tasks and energy.",
                style: const TextStyle(height: 1.35),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SolidAction(
                      label: plan == null ? 'Plan my day' : "View today's plan",
                      onTap: openPlan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => showInfoDialog(
                      context,
                      plan == null ? 'How planning works' : 'Why this plan?',
                      plan == null
                          ? 'Omnia looks at your exams, backlog, open tasks, activity, sleep and yesterday, '
                                'then schedules the rest of your day. Open Plan to create it.'
                          : [
                              ...plan.adjustments,
                              ...plan.tips,
                              plan.sourceLabel,
                            ].join('\n\n'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.cardForeground(lilac, prominent: true),
                      side: BorderSide(color: context.foreground, width: 1.5),
                    ),
                    child: const Text('Why?'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.menu_book_outlined,
                title: 'Study',
                amount: hoursLabel(today.studyMinutes),
                goal: '/ ${hoursLabel(today.studyGoalMinutes)}',
                progress: ratio(today.studyMinutes, today.studyGoalMinutes),
                color: blue,
                onTap: openTrack,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CategoryCard(
                icon: Icons.task_alt,
                title: 'Tasks',
                amount: '${today.tasksCompleted} / ${today.taskGoal}',
                goal: 'done today',
                progress: ratio(today.tasksCompleted, today.taskGoal),
                color: yellow,
                onTap: () => _push(context, const TasksPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.directions_run,
                title: 'Activity',
                amount: thousands(today.steps),
                goal: '/ ${thousands(today.stepGoal)}${today.workoutDone ? ' · workout ✓' : ''}',
                progress: ratio(today.steps, today.stepGoal),
                color: mint,
                onTap: openTrack,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CategoryCard(
                icon: Icons.dark_mode_outlined,
                title: 'Sleep',
                amount: today.sleepMinutes == null ? 'Not logged' : hoursLabel(today.sleepMinutes!),
                goal: '/ ${hoursLabel(today.sleepGoalMinutes)}',
                progress: ratio(today.sleepMinutes ?? 0, today.sleepGoalMinutes),
                color: lilac,
                onTap: () => _push(context, const SleepLogPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text('Next up', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            TextButton(onPressed: openPlan, child: const Text('See all →')),
          ],
        ),
        ..._nextUp(context),
        const SizedBox(height: 18),
      ],
    );
  }

  List<Widget> _nextUp(BuildContext context) {
    final plan = data.plan;
    if (plan != null) {
      final upcoming = plan.upcoming(nowHhmm());
      if (upcoming.isEmpty) {
        return [const _Quiet('Nothing else planned today. Nice work.')];
      }
      return [
        for (final item in upcoming)
          AgendaLine(
            onTap: () => openPlanItem(context, item),
            time: item.start,
            title: item.title,
            duration: formatMinutes(item.minutes),
            icon: planStyle(item).icon,
            color: planStyle(item).color,
          ),
      ];
    }
    final lines = <Widget>[
      for (final block in data.studyToday.take(2))
        AgendaLine(
          onTap: openPlan,
          time: 'Study',
          title: '${block.subjectName}: ${block.title}',
          duration: formatMinutes(block.minutes),
          icon: Icons.menu_book_outlined,
          color: blue,
        ),
      for (final task in data.upcomingTasks.take(3))
        AgendaLine(
          onTap: () => _push(context, const TasksPage()),
          time: 'Task',
          title: task.title,
          duration: task.estimatedDuration == null ? '' : formatMinutes(task.estimatedDuration!.inMinutes),
          icon: Icons.task_alt,
          color: yellow,
        ),
    ];
    return lines.isEmpty
        ? [const _Quiet('Nothing scheduled yet. Add tasks or study topics, then plan your day.')]
        : lines;
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: TextStyle(color: context.mutedForeground)),
  );
}
