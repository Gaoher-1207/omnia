import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.time,
    required this.title,
    required this.duration,
    required this.icon,
    required this.color,
    required this.onTap,
    this.showTimeline = true,
    this.showChevron = false,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool showTimeline;
  final bool showChevron;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        if (showTimeline)
          SizedBox(
            width: 52,
            child: Text(
              time,
              style: TextStyle(color: context.mutedForeground, fontSize: 12),
            ),
          ),
        if (showTimeline)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: context.cardColor(color),
              shape: BoxShape.circle,
            ),
          ),
        if (showTimeline) const SizedBox(width: 9),
        Expanded(
          child: Material(
            color: context.cardColor(color),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: context.foreground, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      showTimeline ? duration : "$time \u00b7 $duration",
                      style: TextStyle(color: context.foreground, fontSize: 12),
                    ),
                    if (showChevron)
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: context.foreground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
