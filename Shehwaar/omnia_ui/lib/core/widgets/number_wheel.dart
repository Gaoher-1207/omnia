import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// A scrollable column of whole numbers (hours, minutes…) in OMNIA's bordered
/// style. The chosen value sits in the outlined band in the middle and stays
/// visible. Built on Flutter's own [CupertinoPicker], which screen readers can
/// step through with increase/decrease.
class NumberWheel extends StatefulWidget {
  const NumberWheel({
    super.key,
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
    this.format,
    this.width = 84,
  });

  /// Names the wheel for screen readers, e.g. "Hours".
  final String label;
  final List<int> values;

  /// Must be one of [values].
  final int value;
  final ValueChanged<int> onChanged;

  /// How each value is shown; defaults to the number.
  final String Function(int value)? format;
  final double width;

  @override
  State<NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<NumberWheel> {
  late final _scroll = FixedExtentScrollController(
    initialItem: widget.values
        .indexOf(widget.value)
        .clamp(0, widget.values.length - 1),
  );

  @override
  void didUpdateWidget(NumberWheel old) {
    super.didUpdateWidget(old);
    final index = widget.values.indexOf(widget.value);
    if (index >= 0 && index != _scroll.selectedItem && _scroll.hasClients) {
      _scroll.jumpToItem(index);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = MediaQuery.textScalerOf(context).scale(38).clamp(38.0, 76.0);
    final format = widget.format ?? (value) => '$value';
    return Semantics(
      label: widget.label,
      child: Container(
        width: MediaQuery.textScalerOf(context)
            .scale(widget.width)
            .clamp(widget.width, widget.width * 1.8),
        // Three rows: the chosen value with one neighbour each side, so the
        // wheel stays compact enough to scroll the page past it.
        height: item * 3,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.outline, width: 1.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            textTheme: CupertinoTextThemeData(
              pickerTextStyle: TextStyle(
                fontFamily: archivo,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.foreground,
              ),
            ),
          ),
          child: CupertinoPicker(
            scrollController: _scroll,
            itemExtent: item,
            squeeze: 1.1,
            diameterRatio: 1.4,
            selectionOverlay: _SelectionBand(),
            onSelectedItemChanged: (index) =>
                widget.onChanged(widget.values[index]),
            children: [
              for (final value in widget.values)
                Center(child: Text(format(value), textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The outlined band marking the chosen value.
class _SelectionBand extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: context.foreground.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.outline, width: 1.6),
    ),
  );
}
