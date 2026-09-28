import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';

/// Calendar dates supplied by the backend, never converted to UTC instants.
class PlanDateStrip extends StatefulWidget {
  const PlanDateStrip({
    super.key,
    required this.today,
    required this.selected,
    required this.onSelect,
  });
  final DateTime today, selected;
  final ValueChanged<DateTime?> onSelect;
  @override
  State<PlanDateStrip> createState() => _PlanDateStripState();
}

class _PlanDateStripState extends State<PlanDateStrip> {
  late DateTime _anchor = widget.selected;
  final _scroll = ScrollController(initialScrollOffset: 30 * 104);
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _center(DateTime date) {
    setState(() => _anchor = date);
    _scroll.jumpTo(30 * 104);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          TextButton(
            onPressed: () {
              _center(widget.today);
              widget.onSelect(null);
            },
            child: const Text('Today'),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Choose date',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: widget.selected,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null && mounted) {
                _center(date);
                widget.onSelect(date);
              }
            },
          ),
        ],
      ),
      SingleChildScrollView(
        key: const ValueKey('plan-date-strip'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            for (var offset = -30; offset <= 30; offset++) _day(offset),
          ],
        ),
      ),
    ],
  );

  Widget _day(int offset) {
    final day = DateTime(_anchor.year, _anchor.month, _anchor.day + offset);
    final selected = DateUtils.isSameDay(day, widget.selected);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 96,
        child: Semantics(
          selected: selected,
          label: '${day.year}-${day.month}-${day.day}',
          child: HardCard(
            color: selected ? yellow : paper,
            onTap: () => widget.onSelect(day),
            child: Column(
              children: [
                Text(names[day.weekday - 1]),
                Text(
                  '${day.day}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
