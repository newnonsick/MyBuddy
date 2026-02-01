import 'package:flutter/material.dart';

import '../../../../core/google/google_calendar_service.dart';
import '../../../../shared/widgets/glass/glass.dart';

class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.selectedDate,
    required this.events,
    required this.isLoading,
    required this.onDeleteEvent,
  });

  final DateTime selectedDate;
  final List<CalendarEvent> events;
  final bool isLoading;
  final ValueChanged<String> onDeleteEvent;

  @override
  Widget build(BuildContext context) {
    final dayEvents = _getEventsForDate(selectedDate);

    if (isLoading && dayEvents.isEmpty) {
      return SliverToBoxAdapter(child: _buildLoadingState(context));
    }

    if (dayEvents.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState(context));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final event = dayEvents[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: EventCard(
            event: event,
            onDelete: () => onDeleteEvent(event.id),
          ),
        );
      }, childCount: dayEvents.length),
    );
  }

  List<CalendarEvent> _getEventsForDate(DateTime date) {
    return events.where((event) {
      final eventDate = event.startTime;
      return eventDate.year == date.year &&
          eventDate.month == date.month &&
          eventDate.day == date.day;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Widget _buildLoadingState(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading events...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No events scheduled',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to add a new event',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onDelete});

  final CalendarEvent event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimeIndicator(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (event.description != null &&
                    event.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (event.location != null && event.location!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: Colors.white.withValues(alpha: 0.6),
              size: 20,
            ),
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Delete'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeIndicator(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            event.isAllDay ? 'All' : _formatTime(event.startTime),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
          ),
          if (!event.isAllDay) ...[
            Text(
              'to',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            Text(
              _formatTime(event.endTime),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: primaryColor.withValues(alpha: 0.8),
              ),
            ),
          ] else
            Text(
              'Day',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: primaryColor.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute';
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event?'),
        content: Text(
          'Are you sure you want to delete "${event.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              onDelete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
