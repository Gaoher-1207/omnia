import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';

/// Entry point to the shared Focus Timer: a plain "Open" action when idle, a
/// compact live view of the same app-level controller once a phase is started.
class FocusTimerEntry extends StatelessWidget {
  const FocusTimerEntry({super.key});

  static void _open(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const FocusTimerPage()),
  );

  @override
  Widget build(BuildContext context) {
    final timer = FocusTimerScope.of(context);
    if (!timer.inProgress) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.timer_outlined, size: 18),
          label: const Text('Open Focus Timer'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.foreground,
            padding: const EdgeInsets.symmetric(vertical: 15),
            side: BorderSide(color: context.outline, width: 1.5),
          ),
        ),
      );
    }
    final focus = timer.phase == FocusPhase.focus;
    final color = focus ? blue : mint;
    final foreground = context.cardForeground(color);
    return Semantics(
      button: true,
      label: 'Open Focus Timer',
      child: HardCard(
        color: color,
        onTap: () => _open(context),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 56,
              child: CircularProgressIndicator(
                // Drains from full to empty as the phase runs out.
                value: 1 - timer.progress,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: foreground,
                backgroundColor: context.progressTrack(color),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LabelTag(text: focus ? 'FOCUS' : 'BREAK'),
                      if (timer.paused) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Paused',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCountdown(timer.remaining),
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: foreground),
          ],
        ),
      ),
    );
  }
}
