import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/google/google_auth_service.dart';
import '../../../../core/google/google_calendar_service.dart';
import '../../../../shared/widgets/glass/glass.dart';
import '../google_calendar_controller.dart';
import '../widgets/account_menu.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/calendar_grid.dart';
import '../widgets/calendar_header.dart';
import '../widgets/event_list.dart';
import '../widgets/google_sign_in_prompt.dart';

class GoogleCalendarPage extends ConsumerStatefulWidget {
  const GoogleCalendarPage({super.key});

  @override
  ConsumerState<GoogleCalendarPage> createState() => _GoogleCalendarPageState();
}

class _GoogleCalendarPageState extends ConsumerState<GoogleCalendarPage> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndLoadEvents();
    });
  }

  Future<void> _initializeAndLoadEvents() async {
    final authService = ref.read(googleAuthServiceProvider);

    await authService.ensureInitialized();

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });

      if (authService.isSignedIn) {
        await _loadEventsIfSignedIn();
      }
    }
  }

  Future<void> _loadEventsIfSignedIn() async {
    final authService = ref.read(googleAuthServiceProvider);
    if (authService.isSignedIn) {
      final calendarService = ref.read(googleCalendarServiceProvider);
      final controller = ref.read(googleCalendarControllerProvider);
      final result = await calendarService.fetchMonthEvents(
        month: controller.currentMonth,
      );
      if (result.isFailure && mounted && result.error != null) {
        _showError(result.error!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = ref.watch(googleAuthServiceProvider);
    final calendarService = ref.watch(googleCalendarServiceProvider);
    final controller = ref.watch(googleCalendarControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, authService),
            Expanded(
              child: _buildContent(
                context,
                authService,
                calendarService,
                controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, GoogleAuthService authService) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GlassIconButton.panel(
            tooltip: 'Back',
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Calendar',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (authService.isSignedIn) ...[
            GlassIconButton.panel(
              tooltip: 'Today',
              icon: Icons.today_rounded,
              onPressed: () {
                ref.read(googleCalendarControllerProvider).goToToday();
                unawaited(_loadEventsIfSignedIn());
              },
            ),
            const SizedBox(width: 8),
            AccountMenu(authService: authService),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    GoogleAuthService authService,
    GoogleCalendarService calendarService,
    GoogleCalendarController controller,
  ) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (authService.errorMessage != null) {
      return _buildErrorState(authService.errorMessage!, () {
        authService.clearError();
      });
    }

    if (!authService.isSignedIn) {
      return GoogleSignInPrompt(
        authService: authService,
        onSignInComplete: _loadEventsIfSignedIn,
      );
    }

    if (calendarService.errorMessage != null &&
        calendarService.events.isEmpty) {
      return _buildErrorState(calendarService.errorMessage!, () {
        calendarService.clearError();
      });
    }

    return RefreshIndicator(
      onRefresh: _loadEventsIfSignedIn,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: const Color(0xFF1A1A1D),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CalendarHeader(
                currentMonth: controller.currentMonth,
                onPreviousMonth: () {
                  controller.previousMonth();
                  unawaited(_loadEventsIfSignedIn());
                },
                onNextMonth: () {
                  controller.nextMonth();
                  unawaited(_loadEventsIfSignedIn());
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CalendarGrid(
                currentMonth: controller.currentMonth,
                selectedDate: controller.selectedDate,
                events: calendarService.events,
                onDateSelected: (date) {
                  controller.selectDate(date);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildEventsHeader(controller, calendarService),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: EventList(
              selectedDate: controller.selectedDate ?? DateTime.now(),
              events: calendarService.events,
              isLoading: calendarService.isLoading,
              onEditEvent: (event) {
                _showAddEventSheet(
                  controller.selectedDate,
                  initialEvent: event,
                );
              },
              onDeleteEvent: (eventId) async {
                final result = await calendarService.deleteEvent(eventId);
                if (result.isFailure && mounted) {
                  _showError(result.error!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsHeader(
    GoogleCalendarController controller,
    GoogleCalendarService calendarService,
  ) {
    final selectedDate = controller.selectedDate ?? DateTime.now();
    final dateStr = _formatDate(selectedDate);

    return Row(
      children: [
        Icon(
          Icons.event_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Events for $dateStr',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        if (calendarService.isLoading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          GlassIconButton.pill(
            tooltip: 'Add Event',
            icon: Icons.add_rounded,
            onPressed: () => _showAddEventSheet(controller.selectedDate),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);

    if (target == today) {
      return 'Today';
    } else if (target == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else if (target == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  void _showAddEventSheet(
    DateTime? selectedDate, {
    CalendarEvent? initialEvent,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEventSheet(
        initialDate: selectedDate ?? initialEvent?.startTime ?? DateTime.now(),
        initialEvent: initialEvent,
        onEventSaved: () {
          _loadEventsIfSignedIn();
        },
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback onDismiss) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onDismiss,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
