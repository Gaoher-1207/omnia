import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';

/// A small, known set of choices. Side-by-side segments at normal text
/// sizes; at large accessibility sizes, where segment labels would break
/// mid-word, the same choices open as a list instead.
class ChoiceSegments<T> extends StatelessWidget {
  const ChoiceSegments({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.showLabel = true,
  });

  /// Names the choice; shown as the field label at large text sizes.
  final String label;
  final List<SelectOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Whether the label also heads the segments at normal text sizes.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(14) <= 14 * 1.3) {
      final segments = SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final option in options)
            ButtonSegment(value: option.value, label: Text(option.label)),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => onChanged(selection.single),
      );
      if (!showLabel) return segments;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          segments,
        ],
      );
    }
    return PickerField(
      label: label,
      value: options.where((o) => o.value == selected).firstOrNull?.label,
      onTap: () async {
        final picked = await showSelectSheet(
          context,
          title: label,
          options: options,
          selected: selected,
        );
        if (picked != null) onChanged(picked.value);
      },
    );
  }
}
