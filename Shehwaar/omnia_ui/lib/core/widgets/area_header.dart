import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/accent_circle.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';

/// The top of an area's screen (Activity, Sleep, Study…): its accent, icon,
/// name and one line of context, so a deep screen reads as part of OMNIA.
class AreaHeader extends StatelessWidget {
  const AreaHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.tag,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;

  /// A short context label above the title, e.g. "Today", "Last night".
  final String? eyebrow;
  final String? tag;

  @override
  Widget build(BuildContext context) => HardCard(
    color: color,
    child: Row(
      children: [
        AccentCircle(color: color, size: 46, icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Text(eyebrow!.toUpperCase(), style: OmniaText.label),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle),
              if (tag != null) ...[
                const SizedBox(height: 8),
                LabelTag(text: tag!),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
