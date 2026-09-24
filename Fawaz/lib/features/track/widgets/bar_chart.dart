import 'package:flutter/material.dart';

/// A small dependency-free bar chart in the card style: one bar per day, a
/// dashed-look goal line, and an optional dot under highlighted days.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.goal,
    this.highlights,
    this.caption,
    this.height = 120,
  });

  final List<double> values;
  final List<String> labels;

  /// Bars, labels and the goal line; pass the card's foreground colour.
  final Color color;
  final double? goal;
  final List<bool>? highlights;
  final String? caption;
  final double height;

  @override
  Widget build(BuildContext context) {
    final foreground = color;
    var top = goal ?? 0.0;
    for (final v in values) {
      if (v > top) top = v;
    }
    if (top <= 0) top = 1;
    final goalLine = goal == null || goal! <= 0 ? null : goal! / top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null) ...[
          Text(caption!, style: TextStyle(fontSize: 12, color: foreground)),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: height,
          child: Stack(
            children: [
              if (goalLine != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * goalLine,
                  child: Container(height: 1.5, color: foreground.withValues(alpha: .55)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message: values[i].round().toString(),
                          child: Container(
                            height: (height * values[i] / top).clamp(2.0, height),
                            decoration: BoxDecoration(
                              color: goal != null && values[i] >= goal!
                                  ? foreground
                                  : foreground.withValues(alpha: .35),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(labels[i], style: TextStyle(fontSize: 10, color: foreground)),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: highlights != null && highlights![i] ? foreground : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
