import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/action_row.dart';
import 'package:omnia_ui/core/widgets/area_header.dart';
import 'package:omnia_ui/core/widgets/section_header.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/study/exam_form_page.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/widgets/exam_card.dart';

/// One upcoming exam, read live from [StudyController] so an edit shows at
/// once.
class ExamDetailPage extends StatelessWidget {
  const ExamDetailPage({super.key, required this.examId});
  final String examId;

  static void open(BuildContext context, String examId) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => ExamDetailPage(examId: examId)),
  );

  Future<void> _delete(BuildContext context, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete exam?'),
        content: Text('“$title” will be removed.'),
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
      if (await StudyScope.read(context).deleteExam(examId) == null) return;
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
      return;
    }
    if (!context.mounted) return;
    showDone(
      context,
      studySavedMessage(
        'Exam deleted',
        todayStale: DashboardScope.read(context).loadError != null,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final exam = StudyScope.of(context).exam(examId);
    return Scaffold(
      appBar: AppBar(),
      body: exam == null
          ? const MessageView(
              title: 'This exam is no longer upcoming.',
              detail: 'It was deleted, or its date has passed.',
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                AreaHeader(
                  icon: Icons.event_note_outlined,
                  color: blue,
                  eyebrow: examCountdown(exam.daysLeft),
                  title: exam.title,
                  subtitle:
                      '${exam.subjectName}  ·  ${formatLongDate(exam.date)}',
                ),
                const SizedBox(height: 18),
                ActionRow(
                  primary: SolidAction(
                    label: 'Edit',
                    onTap: () => ExamFormPage.open(context, initial: exam),
                  ),
                  secondary: [
                    OutlineAction(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      onPressed: () => _delete(context, exam.title),
                    ),
                  ],
                ),
                if (exam.notes case final notes?) ...[
                  const SizedBox(height: 24),
                  const SectionHeader('Notes'),
                  Text(notes, style: TextStyle(color: context.foreground)),
                ],
              ],
            ),
    );
  }
}
