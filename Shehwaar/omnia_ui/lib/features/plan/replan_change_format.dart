import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';

/// One short line per visible change in a replan preview: the action and the
/// item title only ("Moved Assignment"). UNCHANGED operations are omitted.
/// Times, reasons and other proposal details stay out of the preview.
List<String> describeReplanChanges(Iterable<ReplanOperation> operations) => [
  for (final operation in operations) ?describeReplanChange(operation),
];

/// The line for [operation], or null when it should not be shown.
String? describeReplanChange(ReplanOperation operation) {
  final verb = switch (operation.kind) {
    'ADD' => 'Added',
    'REMOVE' => 'Removed',
    'MOVE' => 'Moved',
    'RESCHEDULE' => 'Rescheduled',
    'SHORTEN' => 'Shortened',
    _ => null,
  };
  if (verb == null) return null;
  final title =
      _title(operation.after) ?? _title(operation.before) ?? 'an item';
  return '$verb $title';
}

String? _title(Map<String, dynamic>? values) {
  final title = values?['title'];
  return title is String && title.trim().isNotEmpty ? title.trim() : null;
}
