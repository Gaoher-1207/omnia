import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// A field whose value is picked rather than typed (a choice, a date, a
/// time). Looks like every other OMNIA field; a tap runs [onTap].
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.expand_more,
    this.helperText,
    this.errorText,
    this.onClear,
    this.clearTooltip,
  });
  final String label;

  /// What is shown; null reads as not set.
  final String? value;
  final VoidCallback? onTap;
  final IconData icon;
  final String? helperText, errorText;

  /// Shows a clear button while a value is set.
  final VoidCallback? onClear;
  final String? clearTooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: value ?? 'Not set',
      onTap: onTap,
      excludeSemantics: onClear == null || value == null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            enabled: enabled,
            labelText: label,
            helperText: helperText,
            helperMaxLines: 3,
            errorText: errorText,
            errorMaxLines: 3,
            suffixIcon: onClear != null && value != null
                ? IconButton(
                    tooltip: clearTooltip ?? 'Clear $label',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  )
                : Icon(icon, color: context.foreground),
          ),
          child: Text(
            value ?? 'Not set',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: value == null ? context.mutedForeground : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in a [SelectField].
class SelectOption<T> {
  const SelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// A known, finite choice: shows the current option and opens a sheet of
/// all of them. [searchable] adds a filter box for long lists.
class SelectField<T> extends FormField<T> {
  SelectField({
    super.key,
    required String label,
    required List<SelectOption<T>> options,
    super.initialValue,
    ValueChanged<T>? onChanged,
    String? helperText,
    String? errorText,
    bool searchable = false,
    super.validator,
  }) : super(
         builder: (field) {
           final current = options
               .where((option) => option.value == field.value)
               .firstOrNull;
           return PickerField(
             label: label,
             value: current?.label,
             helperText: helperText,
             errorText: errorText ?? field.errorText,
             onTap: () async {
               final picked = await showSelectSheet(
                 field.context,
                 title: label,
                 options: options,
                 selected: field.value,
                 searchable: searchable,
               );
               if (picked == null) return;
               field.didChange(picked.value);
               onChanged?.call(picked.value);
             },
           );
         },
       );
}

/// The picked option, or null when the sheet was dismissed.
Future<SelectOption<T>?> showSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<SelectOption<T>> options,
  T? selected,
  bool searchable = false,
}) => showModalBottomSheet<SelectOption<T>>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => _SelectSheet<T>(
    title: title,
    options: options,
    selected: selected,
    searchable: searchable,
  ),
);

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
  });
  final String title;
  final List<SelectOption<T>> options;
  final T? selected;
  final bool searchable;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final option in widget.options)
        if (option.label.toLowerCase().contains(query)) option,
    ];
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (text) => setState(() => _query = text),
                ),
              ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      child: Text(
                        'Nothing matches “${_query.trim()}”.',
                        style: TextStyle(color: context.mutedForeground),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      children: [
                        for (final option in shown)
                          _OptionRow(
                            label: option.label,
                            selected: option.value == widget.selected,
                            onTap: () => Navigator.pop(context, option),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? context.cardColor(lilac) : Colors.transparent;
    final foreground = selected
        ? context.cardForeground(lilac)
        : context.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? context.outlineOn(fill) : context.outline,
              width: selected ? 1.8 : 1.2,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected) Icon(Icons.check, color: foreground),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
