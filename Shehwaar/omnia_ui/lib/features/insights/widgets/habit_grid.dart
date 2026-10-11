import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/insights/activity_insights.dart';

/// A compact habit calendar: one bordered square per day in Monday-first
/// columns. Filled = hit, outlined = logged without it, dotted = not logged.
class HabitGrid extends StatelessWidget {
  const HabitGrid({
    super.key,
    required this.days,
    required this.stateOf,
    required this.accent,
    required this.describe,
  });
  final List<InsightDay> days;
  final DayState Function(InsightDay) stateOf;
  final Color accent;

  /// Screen-reader text for one day, after its date.
  final String Function(InsightDay, DayState) describe;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cell = ((constraints.maxWidth - _gap * 6) / 7).clamp(14.0, 40.0);
      final leading = days.isEmpty ? 0 : days.first.day.weekday - 1;
      final slots = <InsightDay?>[
        for (var i = 0; i < leading; i++) null,
        ...days,
      ];
      final rows = <List<InsightDay?>>[
        for (var i = 0; i < slots.length; i += 7)
          slots.sublist(i, (i + 7).clamp(0, slots.length)),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (final (index, letter) in _weekdayLetters.indexed) ...[
                  if (index > 0) const SizedBox(width: _gap),
                  SizedBox(
                    width: cell,
                    child: Text(
                      letter,
                      textAlign: TextAlign.center,
                      style: OmniaText.label.copyWith(
                        color: context.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: _gap),
            Row(
              children: [
                for (final (column, day) in row.indexed) ...[
                  if (column > 0) const SizedBox(width: _gap),
                  if (day == null)
                    SizedBox.square(dimension: cell)
                  else
                    Semantics(
                      // Its own node, so each day can be read on its own.
                      container: true,
                      label:
                          '${formatLongDate(day.day)}: '
                          '${describe(day, stateOf(day))}',
                      child: HabitCell(
                        state: stateOf(day),
                        accent: accent,
                        size: cell,
                      ),
                    ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );
}

class HabitCell extends StatelessWidget {
  const HabitCell({
    super.key,
    required this.state,
    required this.accent,
    required this.size,
  });
  final DayState state;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size < 20 ? 4 : 7);
    final fill = context.cardColor(accent);
    return switch (state) {
      DayState.hit => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: Border.all(color: context.outlineOn(fill), width: 1.5),
        ),
      ),
      DayState.logged => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: radius,
          border: Border.all(color: context.outline, width: 1.5),
        ),
      ),
      DayState.notLogged => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: context.mutedForeground.withValues(alpha: .35),
          ),
        ),
        child: Container(
          width: (size / 5).clamp(2.0, 5.0),
          height: (size / 5).clamp(2.0, 5.0),
          decoration: BoxDecoration(
            color: context.mutedForeground.withValues(alpha: .55),
            shape: BoxShape.circle,
          ),
        ),
      ),
      // Keeps the calendar's shape without looking like a day with data.
      DayState.upcoming => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.mutedForeground.withValues(alpha: .08),
          borderRadius: radius,
        ),
      ),
    };
  }
}
