import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';

/// Mock mode's Ask Omnia: canned sample answers about the demo day (the DBMS
/// exam in 8 days, the assignment, 135 of 240 study minutes). No model is
/// involved; the page labels these answers as samples.
class MockAssistantRepository implements AssistantRepository {
  MockAssistantRepository({this.delay = const Duration(milliseconds: 700)});

  /// Long enough to show the thinking state, like a real answer would.
  final Duration delay;

  static const _answers = [
    (
      ['exam', 'test'],
      'Your next exam is the DBMS exam in 8 days. It is the only one on the '
          'sample day, so a 45-minute revision block today keeps you on track.',
    ),
    (
      ['task', 'urgent', 'due', 'assignment'],
      'Complete Assignment is your only open task, and it is due today. '
          'Finish it first, then move on to DBMS revision.',
    ),
    (
      ['work out', 'workout', 'exercise', 'gym'],
      'Study first: you are at 135 of 240 study minutes and the DBMS exam is '
          'in 8 days. A short walk afterwards would also lift your 6,240 steps '
          'toward 8,000.',
    ),
    (
      ['doing', 'progress', 'how am i'],
      'A solid start: 135 of 240 study minutes, 6,240 of 8,000 steps and '
          '6h 42m of sleep last night against an 8-hour target.',
    ),
  ];

  static const _fallback =
      'Tonight, finish Complete Assignment first, then do a focused DBMS '
      'revision session: the exam is in 8 days and you still have 105 study '
      'minutes left today. You slept 6h 42m, so keep sessions short and aim '
      'for an earlier night.';

  @override
  Future<String> ask(String message, List<AssistantMessage> history) async {
    await Future<void>.delayed(delay);
    final question = message.toLowerCase();
    for (final (keywords, answer) in _answers) {
      if (keywords.any(question.contains)) return answer;
    }
    return _fallback;
  }
}
