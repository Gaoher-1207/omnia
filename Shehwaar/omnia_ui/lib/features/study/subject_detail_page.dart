import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/action_row.dart';
import 'package:omnia_ui/core/widgets/area_header.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/study/exam_detail_page.dart';
import 'package:omnia_ui/features/study/exam_form_page.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/subject_form_page.dart';
import 'package:omnia_ui/features/study/widgets/exam_card.dart';

/// One subject and its upcoming exams, read live from [StudyController].
class SubjectDetailPage extends StatelessWidget {
  const SubjectDetailPage({super.key, required this.subjectId});
  final String subjectId;

  static void open(BuildContext context, String subjectId) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SubjectDetailPage(subjectId: subjectId),
        ),
      );

  Future<void> _delete(BuildContext context, String name, int exams) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text(
          exams == 0
              ? '“$name” will be removed.'
              : '“$name” and its $exams upcoming '
                    '${exams == 1 ? 'exam' : 'exams'} will be removed. '
                    'Study time you logged is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      if (await StudyScope.read(context).deleteSubject(subjectId) == null) {
        return;
      }
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
      return;
    }
    if (!context.mounted) return;
    showDone(
      context,
      studySavedMessage(
        'Subject deleted',
        todayStale: DashboardScope.read(context).loadError != null,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final study = StudyScope.of(context);
    final subject = study.subject(subjectId);
    if (subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const MessageView(title: 'This subject was deleted.'),
      );
    }
    final exams = study.examsFor(subjectId);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AreaHeader(
            icon: Icons.menu_book_outlined,
            color: blue,
            eyebrow: 'Subject',
            title: subject.name,
            subtitle: switch (exams.length) {
              0 => 'No upcoming exams',
              1 => '1 upcoming exam',
              final n => '$n upcoming exams',
            },
          ),
          const SizedBox(height: 18),
          ActionRow(
            primary: SolidAction(
              label: 'Add exam',
              onTap: () => ExamFormPage.open(context, subjectId: subjectId),
            ),
            secondary: [
              OutlineAction(
                icon: Icons.edit_outlined,
                label: 'Rename',
                onPressed: () =>
                    SubjectFormPage.open(context, initial: subject),
              ),
              OutlineAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                onPressed: () => _delete(context, subject.name, exams.length),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader('Upcoming exams'),
          if (exams.isEmpty)
            EmptyCard(
              title: 'No upcoming exams for ${subject.name}.',
              action: SolidAction(
                label: 'Add exam',
                onTap: () => ExamFormPage.open(context, subjectId: subjectId),
              ),
            ),
          for (final exam in exams)
            ExamCard(
              exam: exam,
              showSubject: false,
              onTap: () => ExamDetailPage.open(context, exam.id),
            ),
        ],
      ),
    );
  }
}
