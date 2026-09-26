import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/area_header.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';

/// Study's home: today's study time and the next exam, as the dashboard
/// reports them, and the Focus Timer. Subjects, exams and sessions of its
/// own arrive with Study's backend integration.
class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  static void open(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const StudyPage()),
  );

  @override
  Widget build(BuildContext context) {
    final dashboard = DashboardScope.of(context);
    final today = dashboard.dashboard?.today;
    final exam = dashboard.dashboard?.nextExam;
    final sample = AppDependenciesScope.of(context).sampleContent;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AreaHeader(
            icon: Icons.menu_book_outlined,
            color: blue,
            eyebrow: 'Today',
            title: 'Study',
            subtitle: today == null
                ? (dashboard.loading ? 'Loading…' : "Couldn't load today")
                : today.studyGoalMinutes == 0
                ? '${formatMinutes(today.studyMinutes)} studied'
                : '${formatMinutes(today.studyMinutes)} of '
                      '${formatMinutes(today.studyGoalMinutes)} studied',
          ),
          if (today != null && today.studyGoalMinutes > 0) ...[
            const SizedBox(height: 10),
            OmniaProgressBar(
              value: towards(today.studyMinutes, today.studyGoalMinutes),
              color: paper,
              height: 10,
              semanticsLabel: 'Study progress',
            ),
          ],
          const SizedBox(height: 24),
          const SectionHeader('Next exam'),
          if (exam == null)
            EmptyCard(
              title: dashboard.dashboard == null
                  ? 'Waiting for today…'
                  : 'No exams coming up.',
              detail: 'Upcoming exams will count down here.',
            )
          else
            HardCard(
              color: blue,
              shadowOffset: const Offset(2, 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    examHeadline(exam),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${exam.title}  ·  ${formatLongDate(exam.date)}'),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const SectionHeader(
            'Focus',
            detail: 'Timed study blocks with breaks.',
          ),
          const FocusTimerEntry(),
          if (sample) ...[
            const SizedBox(height: 24),
            const SectionHeader('Revision', action: LabelTag(text: 'SAMPLE')),
            HardCard(
              color: blue,
              shadowOffset: const Offset(2, 3),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const RevisionDetailPage()),
              ),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      RevisionScope.of(context).title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
