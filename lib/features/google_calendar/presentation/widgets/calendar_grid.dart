import 'package:flutter/material.dart';

import '../../../../core/google/google_calendar_service.dart';
import '../../../../shared/widgets/glass/glass.dart';

class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    super.key,
    required this.currentMonth,
    required this.selectedDate,
    required this.events,
    required this.onDateSelected,
  });

  final DateTime currentMonth;
  final DateTime? selectedDate;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildWeekDayHeaders(context),
          const SizedBox(height: 8),
          _buildDaysGrid(context),
        ],
      ),
    );
  }

  Widget _buildWeekDayHeaders(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Row(
      children: days.map((day) {
        return Expanded(
          child: Center(
            child: Text(
              day,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDaysGrid(BuildContext context) {
    final days = _getDaysInMonth();
    final rows = <Widget>[];

    for (var i = 0; i < days.length; i += 7) {
      final weekDays = days.sublist(i, (i + 7).clamp(0, days.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: weekDays.map((date) {
              return Expanded(
                child: _DayCell(
                  date: date,
                  isCurrentMonth: date?.month == currentMonth.month,
                  isToday: _isToday(date),
                  isSelected: _isSelected(date),
                  hasEvents: _hasEvents(date),
                  onTap: date != null ? () => onDateSelected(date) : null,
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  List<DateTime?> _getDaysInMonth() {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final startWeekday = firstDay.weekday;

    final days = <DateTime?>[];

    for (var i = 1; i < startWeekday; i++) {
      final prevDay = firstDay.subtract(Duration(days: startWeekday - i));
      days.add(prevDay);
    }

    for (var i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(currentMonth.year, currentMonth.month, i));
    }

    while (days.length % 7 != 0) {
      final nextDay = lastDay.add(
        Duration(days: days.length - lastDay.day - startWeekday + 2),
      );
      days.add(nextDay);
    }

    return days;
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime? date) {
    if (date == null || selectedDate == null) return false;
    return date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
  }

  bool _hasEvents(DateTime? date) {
    if (date == null) return false;
    return events.any((event) {
      final eventDate = event.startTime;
      return eventDate.year == date.year &&
          eventDate.month == date.month &&
          eventDate.day == date.day;
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.onTap,
  });

  final DateTime? date;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return const SizedBox(height: 40);
    }

    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor
              : isToday
              ? primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isToday && !isSelected
              ? Border.all(color: primaryColor, width: 1.5)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${date!.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday || isSelected
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : isCurrentMonth
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
            if (hasEvents && !isSelected)
              Positioned(
                bottom: 4,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
