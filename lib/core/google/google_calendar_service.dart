import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'google_auth_service.dart';

class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.location,
    this.colorId,
  });

  factory CalendarEvent.fromGoogleEvent(calendar.Event event) {
    final start = event.start;
    final end = event.end;

    final isAllDay = start?.date != null;

    DateTime startTime;
    DateTime endTime;

    if (isAllDay) {
      startTime = start!.date!;
      endTime = end?.date ?? startTime.add(const Duration(days: 1));
    } else {
      final utcStart = start?.dateTime ?? DateTime.now();
      final utcEnd = end?.dateTime ?? utcStart.add(const Duration(hours: 1));
      startTime = utcStart.toLocal();
      endTime = utcEnd.toLocal();
    }

    return CalendarEvent(
      id: event.id ?? '',
      title: event.summary ?? '(No title)',
      description: event.description,
      startTime: startTime,
      endTime: endTime,
      isAllDay: isAllDay,
      location: event.location,
      colorId: event.colorId,
    );
  }

  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String? colorId;

  Future<calendar.Event> toGoogleEvent() async {
    final event = calendar.Event();
    event.summary = title;
    event.description = description;
    event.location = location;

    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    final timeZoneName = timeZoneInfo.identifier;

    if (isAllDay) {
      event.start = calendar.EventDateTime(date: startTime);
      event.end = calendar.EventDateTime(date: endTime);
    } else {
      event.start = calendar.EventDateTime(
        dateTime: startTime,
        timeZone: timeZoneName,
      );
      event.end = calendar.EventDateTime(
        dateTime: endTime,
        timeZone: timeZoneName,
      );
    }

    return event;
  }
}

class CalendarResult<T> {
  CalendarResult.success(this.data) : error = null;
  CalendarResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

class GoogleCalendarService extends ChangeNotifier {
  GoogleCalendarService({required this.authService}) {
    authService.addListener(_onAuthChanged);
  }

  final GoogleAuthService authService;

  calendar.CalendarApi? _calendarApi;

  List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => List.unmodifiable(_events);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  bool get isReady => authService.isSignedIn && _calendarApi != null;

  void _onAuthChanged() {
    if (authService.isSignedIn && authService.authClient != null) {
      _calendarApi = calendar.CalendarApi(authService.authClient!);
    } else {
      _calendarApi = null;
      _events = [];
    }
    notifyListeners();
  }

  void setSelectedDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  void _mergeEvents(
    List<CalendarEvent> newEvents,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    _events.removeWhere((event) {
      return !event.startTime.isBefore(rangeStart) &&
          !event.startTime.isAfter(rangeEnd);
    });

    _events.addAll(newEvents);

    _events.sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<CalendarResult<List<CalendarEvent>>> fetchEvents({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!authService.isSignedIn) {
      return CalendarResult.failure('Please sign in to view your calendar.');
    }

    final tokenValid = await authService.ensureValidToken();
    if (!tokenValid) {
      return CalendarResult.failure('Session expired. Please sign in again.');
    }

    _calendarApi ??= calendar.CalendarApi(authService.authClient!);

    _setLoading(true);
    _clearError();

    try {
      final start = startDate ?? _selectedDate;
      final end = endDate ?? start.add(const Duration(days: 1));

      final timeMin = DateTime(start.year, start.month, start.day);
      final timeMax = DateTime(end.year, end.month, end.day, 23, 59, 59);

      final eventsResult = await _calendarApi!.events.list(
        'primary',
        timeMin: timeMin.toUtc(),
        timeMax: timeMax.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 100,
      );

      final fetchedEvents = (eventsResult.items ?? [])
          .where((e) => e.status != 'cancelled')
          .map((e) => CalendarEvent.fromGoogleEvent(e))
          .toList();

      _mergeEvents(fetchedEvents, timeMin, timeMax);
      _setLoading(false);

      return CalendarResult.success(fetchedEvents);
    } catch (e) {
      debugPrint('GoogleCalendarService: Failed to fetch events: $e');
      final error = _parseApiError(e);
      _setError(error);
      _setLoading(false);
      return CalendarResult.failure(error);
    }
  }

  Future<CalendarResult<List<CalendarEvent>>> fetchWeekEvents() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));

    return fetchEvents(startDate: weekStart, endDate: weekEnd);
  }

  Future<CalendarResult<List<CalendarEvent>>> fetchMonthEvents({
    DateTime? month,
  }) async {
    final target = month ?? DateTime.now();
    final monthStart = DateTime(target.year, target.month, 1);
    final monthEnd = DateTime(target.year, target.month + 1, 0);

    return fetchEvents(startDate: monthStart, endDate: monthEnd);
  }

  Future<CalendarResult<CalendarEvent>> createEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    bool isAllDay = false,
    String? location,
  }) async {
    if (!authService.isSignedIn) {
      return CalendarResult.failure('Please sign in to create events.');
    }

    final tokenValid = await authService.ensureValidToken();
    if (!tokenValid) {
      return CalendarResult.failure('Session expired. Please sign in again.');
    }

    _calendarApi ??= calendar.CalendarApi(authService.authClient!);

    _setLoading(true);
    _clearError();

    try {
      final event = CalendarEvent(
        id: '',
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
      );

      final googleEvent = await event.toGoogleEvent();
      final createdEvent = await _calendarApi!.events.insert(
        googleEvent,
        'primary',
      );

      final newEvent = CalendarEvent.fromGoogleEvent(createdEvent);

      _events.add(newEvent);
      _events.sort((a, b) => a.startTime.compareTo(b.startTime));

      _setLoading(false);
      return CalendarResult.success(newEvent);
    } catch (e) {
      debugPrint('GoogleCalendarService: Failed to create event: $e');
      final error = _parseApiError(e);
      _setError(error);
      _setLoading(false);
      return CalendarResult.failure(error);
    }
  }

  Future<CalendarResult<CalendarEvent>> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    bool isAllDay = false,
    String? location,
  }) async {
    if (!authService.isSignedIn) {
      return CalendarResult.failure('Please sign in to edit events.');
    }

    final tokenValid = await authService.ensureValidToken();
    if (!tokenValid) {
      return CalendarResult.failure('Session expired. Please sign in again.');
    }

    _calendarApi ??= calendar.CalendarApi(authService.authClient!);

    _setLoading(true);
    _clearError();

    try {
      final event = CalendarEvent(
        id: eventId,
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
      );

      final googleEvent = await event.toGoogleEvent();
      final updatedEvent = await _calendarApi!.events.update(
        googleEvent,
        'primary',
        eventId,
      );

      final updatedCalendarEvent = CalendarEvent.fromGoogleEvent(updatedEvent);

      final existingIndex = _events.indexWhere((e) => e.id == eventId);
      if (existingIndex >= 0) {
        _events[existingIndex] = updatedCalendarEvent;
      } else {
        _events.add(updatedCalendarEvent);
      }
      _events.sort((a, b) => a.startTime.compareTo(b.startTime));

      _setLoading(false);
      return CalendarResult.success(updatedCalendarEvent);
    } catch (e) {
      debugPrint('GoogleCalendarService: Failed to update event: $e');
      final error = _parseApiError(e);
      _setError(error);
      _setLoading(false);
      return CalendarResult.failure(error);
    }
  }

  Future<CalendarResult<void>> deleteEvent(String eventId) async {
    if (!authService.isSignedIn) {
      return CalendarResult.failure('Please sign in to delete events.');
    }

    final tokenValid = await authService.ensureValidToken();
    if (!tokenValid) {
      return CalendarResult.failure('Session expired. Please sign in again.');
    }

    if (_calendarApi == null) {
      return CalendarResult.failure('Calendar not initialized.');
    }

    _setLoading(true);
    _clearError();

    try {
      await _calendarApi!.events.delete('primary', eventId);

      _events.removeWhere((e) => e.id == eventId);

      _setLoading(false);
      return CalendarResult.success(null);
    } catch (e) {
      debugPrint('GoogleCalendarService: Failed to delete event: $e');
      final error = _parseApiError(e);
      _setError(error);
      _setLoading(false);
      return CalendarResult.failure(error);
    }
  }

  List<CalendarEvent> getEventsForDate(DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    return _events.where((event) {
      final eventDate = DateTime(
        event.startTime.year,
        event.startTime.month,
        event.startTime.day,
      );
      return eventDate == targetDate;
    }).toList();
  }

  void clearEvents() {
    _events = [];
    notifyListeners();
  }

  void clearError() {
    _clearError();
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  String _parseApiError(dynamic error) {
    final message = error.toString().toLowerCase();

    if (message.contains('network') || message.contains('socket')) {
      return 'Network error. Please check your connection.';
    }
    if (message.contains('401') || message.contains('unauthorized')) {
      return 'Authentication failed. Please sign in again.';
    }
    if (message.contains('403') || message.contains('forbidden')) {
      return 'Access denied. Please check calendar permissions.';
    }
    if (message.contains('404') || message.contains('not found')) {
      return 'Calendar or event not found.';
    }
    if (message.contains('429') || message.contains('rate')) {
      return 'Too many requests. Please wait and try again.';
    }
    if (message.contains('500') || message.contains('server')) {
      return 'Google Calendar is temporarily unavailable.';
    }

    return 'An error occurred. Please try again.';
  }

  @override
  void dispose() {
    authService.removeListener(_onAuthChanged);
    super.dispose();
  }
}
