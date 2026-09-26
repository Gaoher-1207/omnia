import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/area_header.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/focus/widgets/focus_timer_entry.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/study/exam_detail_page.dart';
import 'package:omnia_ui/features/study/exam_form_page.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/subject_detail_page.dart';
import 'package:omnia_ui/features/study/subject_form_page.dart';
import 'package:omnia_ui/features/study/widgets/exam_card.dart';

/// Study's home: today's study time (from the dashboard), the user's
/// upcoming exams and subjects (from [StudyController]), and the Focus
/// Timer.
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  static void open(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const StudyPage()),
  );

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  @override
  void initState() {
    super.initState();
    // Fresh on every visit; the last lists stay on screen meanwhile. After
    // the first frame, since loading notifies the page being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StudyScope.read(context).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = DashboardScope.of(context);
    final today = dashboard.dashboard?.today;
    final study = StudyScope.of(context);
    final sample = AppDependenciesScope.of(context).sampleContent;
    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: study.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            AreaHeader(
              icon: Icons.menu_book_outlined,
              color: blue,
              eyebrow: 'Today',
              title: 'Study',
              // Mock mode's subjects and exams are the demo's.
              tag: sample ? 'SAMPLE' : null,
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
            SectionHeader(
              'Upcoming exams',
              action: study.loaded
                  ? _AddButton(
                      label: 'Add exam',
                      onPressed: () => ExamFormPage.open(context),
                    )
                  : null,
            ),
            ..._section(
              study,
              isEmpty: study.exams.isEmpty,
              empty: EmptyCard(
                title: 'No exams yet.',
                detail: 'Add one and Today counts down to it.',
                action: SolidAction(
                  label: 'Add exam',
                  onTap: () => ExamFormPage.open(context),
                ),
              ),
              items: [
                for (final exam in study.exams)
                  ExamCard(
                    exam: exam,
                    onTap: () => ExamDetailPage.open(context, exam.id),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeader(
              'Subjects',
              action: study.loaded
                  ? _AddButton(
                      label: 'Add subject',
                      onPressed: () => SubjectFormPage.open(context),
                    )
                  : null,
            ),
            ..._section(
              study,
              isEmpty: study.subjects.isEmpty,
              empty: EmptyCard(
                title: 'No subjects yet.',
                detail: 'Subjects group your exams.',
                action: SolidAction(
                  label: 'Add subject',
                  onTap: () => SubjectFormPage.open(context),
                ),
              ),
              items: [
                for (final subject in study.subjects)
                  _SubjectRow(
                    name: subject.name,
                    exams: study.examsFor(subject.id).length,
                    onTap: () => SubjectDetailPage.open(context, subject.id),
                  ),
              ],
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
      ),
    );
  }

  /// Loading, a first-load error, the empty state, or the items. Never
  /// "none yet" before the lists have loaded.
  static List<Widget> _section(
    StudyController study, {
    required bool isEmpty,
    required Widget empty,
    required List<Widget> items,
  }) {
    if (!study.loaded) {
      final error = study.loadError;
      return [
        if (error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          EmptyCard(
            title: "Couldn't load your study.",
            detail: friendlyError(error),
            action: SolidAction(label: 'Try again', onTap: study.load),
          ),
      ];
    }
    return isEmpty ? [empty] : items;
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: const Icon(Icons.add),
  );
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.name,
    required this.exams,
    required this.onTap,
  });
  final String name;
  final int exams;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HardCard(
      color: paper,
      shadowOffset: const Offset(2, 3),
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(switch (exams) {
                  0 => 'No upcoming exams',
                  1 => '1 upcoming exam',
                  _ => '$exams upcoming exams',
                }, style: OmniaText.meta),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}
