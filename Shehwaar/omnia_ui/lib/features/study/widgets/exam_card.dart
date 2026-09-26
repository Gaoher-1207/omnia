import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';

/// "Today", "Tomorrow", "In 8 days", from the server's count.
String examCountdown(int daysLeft) => switch (daysLeft) {
  0 => 'Today',
  1 => 'Tomorrow',
  final days => 'In $days days',
};

/// One upcoming exam: title, subject and date, and how soon it is.
class ExamCard extends StatelessWidget {
  const ExamCard({
    super.key,
    required this.exam,
    required this.onTap,
    this.showSubject = true,
  });
  final Exam exam;
  final VoidCallback onTap;

  /// Off where the subject is already the page's context.
  final bool showSubject;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HardCard(
      color: blue,
      shadowOffset: const Offset(2, 3),
      onTap: onTap,
      // The countdown sits above the title, not beside it, so large text
      // never squeezes the title into a sliver.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelTag(text: examCountdown(exam.daysLeft).toUpperCase()),
          const SizedBox(height: 8),
          Text(
            exam.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (showSubject) exam.subjectName,
              formatLongDate(exam.date),
            ].join('  ·  '),
            style: OmniaText.meta,
          ),
        ],
      ),
    ),
  );
}

/// What a finished study change tells the user.
String studySavedMessage(String what, {required bool todayStale}) => todayStale
    ? "$what, but Today couldn't refresh. Pull down on Today to try again."
    : '$what.';
