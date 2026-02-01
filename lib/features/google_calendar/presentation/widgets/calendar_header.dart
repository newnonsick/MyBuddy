import 'package:flutter/material.dart';

import '../../../../shared/widgets/glass/glass.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.currentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime currentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onPreviousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${months[currentMonth.month - 1]} ${currentMonth.year}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(
            onPressed: onNextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
