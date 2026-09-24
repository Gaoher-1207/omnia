import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/focus_session_page.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/plan/revision_actions.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';

/// A study block from today's plan: its topics, time logging and focus timer.
class RevisionDetailPage extends StatefulWidget {
  const RevisionDetailPage({super.key, required this.item});
  final DailyPlanItem item;

  @override
  State<RevisionDetailPage> createState() => _RevisionDetailPageState();
}

class _RevisionDetailPageState extends State<RevisionDetailPage> {
  late final deps = AppDependenciesScope.of(context);
  late final revision = RevisionController(
    repository: deps.study,
    title: widget.item.title,
    minutes: widget.item.minutes,
    start: widget.item.start,
    subjectId: widget.item.subjectId,
    reason: widget.item.detail,
  )..load();
  Exam? _nextExam;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExam());
  }

  Future<void> _loadExam() async {
    final subject = widget.item.subjectId;
    if (subject == null) return;
    try {
      final exams = await deps.study.getExams();
      final match = exams.where((e) => e.subjectId == subject).toList();
      if (mounted && match.isNotEmpty) setState(() => _nextExam = match.first);
    } catch (_) {
      // The exam line is optional; the rest of the page still works.
    }
  }

  @override
  void dispose() {
    revision.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      _changed = true;
    } else {
      showDone(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && _changed) SessionScope.refreshDashboard(context);
    },
    child: RevisionScope(controller: revision, child: Builder(builder: _build)),
  );

  Widget _build(BuildContext context) {
    final revision = RevisionScope.of(context);
    final tasks = revision.tasks;
    final done = revision.done;
    final item = widget.item;
    final plan = ControllerScope.of<PlanController>(context).plan;
    final allDone = revision.sessionLogged && done == tasks.length;
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: Text(revision.title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const HardCard(
                  shadowOffset: Offset(1, 1),
                  color: blue,
                  child: Icon(Icons.menu_book_outlined, size: 32),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(revision.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                      Text('Today  ·  ${item.start} – ${item.end}'),
                      Text('${item.minutes} minutes', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: revision.saving
                        ? 'Saving…'
                        : allDone || (revision.sessionLogged && tasks.isEmpty)
                        ? 'Completed'
                        : 'Mark done',
                    onTap: () => _run(
                      () => revision.markAll(!revision.sessionLogged),
                      "Couldn't save that. Check your connection and try again.",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _smallAction(
                  context,
                  Icons.add,
                  'Topic',
                  item.subjectId == null
                      ? () => showDone(context, 'This block isn’t linked to a subject, so topics can’t be added here.')
                      : () {
                          _changed = true;
                          addRevisionTopic(context, revision);
                        },
                ),
                const SizedBox(width: 8),
                _smallAction(
                  context,
                  Icons.more_horiz,
                  'More',
                  () => showDialog<void>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('Revision actions'),
                      content: const Text('Reset all sub-tasks to incomplete?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialog);
                            _run(revision.resetTopics, "Couldn't reset the topics. Try again.");
                          },
                          child: const Text('Reset sub-tasks'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (revision.sessionLogged) ...[
              const SizedBox(height: 10),
              Text(
                'Logged ${item.minutes} minutes of study for today.',
                style: TextStyle(color: context.mutedForeground),
              ),
            ],
            const SizedBox(height: 20),
            HardCard(
              color: lilac,
              prominent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      OmniaMark(),
                      SizedBox(width: 8),
                      Text('omnia recommends', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.detail == null
                        ? 'Work through the topics below, then mark the session done to log your time.'
                        : '${item.detail}. Work through the topics below, then mark the session done.',
                    style: const TextStyle(height: 1.35),
                  ),
                  if (plan != null && plan.adjustments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        border: Border.all(color: context.outline),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: context.isDark ? context.foreground : null),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('What changed?', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text(plan.adjustments.join('\n')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Coming up', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            HardCard(
              color: paper,
              child: Row(
                children: [
                  const Icon(Icons.event_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _nextExam == null
                          ? 'No exam scheduled for this subject'
                          : '${_nextExam!.title}  ·  '
                                '${_nextExam!.daysLeft == 0 ? 'today' : 'in ${_nextExam!.daysLeft} days'}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 19),
            Text(
              'Sub-tasks  $done/${tasks.length}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            if (!revision.loaded && revision.error == null)
              const LoadingView()
            else if (revision.error != null)
              ErrorView(error: revision.error!, onRetry: revision.load, title: "Couldn't load topics")
            else if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  item.subjectId == null
                      ? 'General study time. Log it with Mark done or the focus timer.'
                      : 'No open topics for this subject. Add one with Topic.',
                  style: TextStyle(color: context.mutedForeground),
                ),
              )
            else
              for (var i = 0; i < tasks.length; i++)
                CheckboxListTile(
                  value: revision.isChecked(i),
                  activeColor: context.colors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tasks[i],
                    style: TextStyle(
                      decoration: revision.isChecked(i) ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  onChanged: (value) => _run(
                    () => revision.setChecked(i, value ?? false),
                    "Couldn't save that change. Try again.",
                  ),
                ),
            const SizedBox(height: 15),
            SolidAction(
              label: 'Start Focus Session',
              onTap: () async {
                final logged = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FocusSessionPage(title: revision.title, subjectId: item.subjectId),
                  ),
                );
                if (logged == true) _changed = true;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction(BuildContext context, IconData icon, String title, VoidCallback onPressed) => Expanded(
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        side: BorderSide(color: context.outline, width: 1.5),
      ),
    ),
  );
}
