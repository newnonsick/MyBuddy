import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'calendar_event_gateway.dart';
import 'google_auth_service.dart';

class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.timeZoneId,
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
  final String? timeZoneId;
  final String? location;
  final String? colorId;

  Future<calendar.Event> toGoogleEvent() async {
    final event = calendar.Event();
    event.summary = title;
    event.description = description;
    event.location = location;

    if (isAllDay) {
      event.start = calendar.EventDateTime(date: startTime);
      event.end = calendar.EventDateTime(date: endTime);
    } else {
      final timeZoneName =
          timeZoneId ?? (await FlutterTimezone.getLocalTimezone()).identifier;
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

final class CalendarResult<T> {
  const CalendarResult.success(this.data) : failure = null;
  const CalendarResult.failure(this.failure) : data = null;

  final T? data;
  final CalendarFailure? failure;

  String? get error => failure?.message;
  bool get isSuccess => failure == null;
  bool get isFailure => failure != null;
}

class GoogleCalendarService extends ChangeNotifier
    implements CalendarEventGateway {
  GoogleCalendarService({required this.authService}) {
    authService.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final GoogleAuthService authService;

  calendar.CalendarApi? _calendarApi;

  int _lastAuthVersion = -1;

  List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => List.unmodifiable(_events);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  bool get isReady => authService.isSignedIn && _calendarApi != null;

  @override
  bool get isAvailable => isReady;

  void _onAuthChanged() {
    if (authService.isSignedIn && authService.authClient != null) {
      _calendarApi = calendar.CalendarApi(authService.authClient!);
      _lastAuthVersion = authService.authClientVersion;
    } else {
      _calendarApi = null;
      _lastAuthVersion = -1;
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

  Future<CalendarFailure?> _ensureFreshApi() async {
    if (!authService.isSignedIn) {
      return const CalendarFailure(
        CalendarFailureCode.notAuthenticated,
        'Please sign in to access your calendar.',
      );
    }

    final tokenValid = await authService.ensureValidToken();
    if (!tokenValid) {
      return const CalendarFailure(
        CalendarFailureCode.notAuthenticated,
        'Session expired. Please sign in again.',
      );
    }

    if (_calendarApi == null ||
        _lastAuthVersion != authService.authClientVersion) {
      _calendarApi = calendar.CalendarApi(authService.authClient!);
      _lastAuthVersion = authService.authClientVersion;
    }

    return null;
  }

  Future<CalendarResult<List<CalendarEvent>>> fetchEvents({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final failure = await _ensureFreshApi();
    if (failure != null) {
      return CalendarResult.failure(failure);
    }

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
      final failure = mapGoogleCalendarFailure(e);
      if (kDebugMode) {
        debugPrint(
          'GoogleCalendarService: fetch failed code=${failure.code.name}',
        );
      }
      _setError(failure.message);
      _setLoading(false);
      return CalendarResult.failure(failure);
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
    String? timeZoneId,
    String? location,
  }) async {
    final failure = await _ensureFreshApi();
    if (failure != null) {
      return CalendarResult.failure(failure);
    }

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
        timeZoneId: timeZoneId,
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
      final failure = mapGoogleCalendarFailure(e);
      if (kDebugMode) {
        debugPrint(
          'GoogleCalendarService: create failed code=${failure.code.name}',
        );
      }
      _setError(failure.message);
      _setLoading(false);
      return CalendarResult.failure(failure);
    }
  }

  @override
  Future<CalendarCreateResult> createCalendarEvent(
    CalendarCreateRequest request,
  ) async {
    final result = await createEvent(
      title: request.title,
      description: request.description,
      startTime: request.startTime,
      endTime: request.endTime,
      isAllDay: request.isAllDay,
      timeZoneId: request.timeZoneId,
      location: request.location,
    );
    final failure = result.failure;
    if (failure != null) return CalendarCreateResult.failure(failure);
    return CalendarCreateResult.success(eventId: result.data?.id);
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
    final failure = await _ensureFreshApi();
    if (failure != null) {
      return CalendarResult.failure(failure);
    }

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
      final failure = mapGoogleCalendarFailure(e);
      if (kDebugMode) {
        debugPrint(
          'GoogleCalendarService: update failed code=${failure.code.name}',
        );
      }
      _setError(failure.message);
      _setLoading(false);
      return CalendarResult.failure(failure);
    }
  }

  Future<CalendarResult<void>> deleteEvent(String eventId) async {
    final failure = await _ensureFreshApi();
    if (failure != null) {
      return CalendarResult.failure(failure);
    }

    _setLoading(true);
    _clearError();

    try {
      await _calendarApi!.events.delete('primary', eventId);

      _events.removeWhere((e) => e.id == eventId);

      _setLoading(false);
      return const CalendarResult.success(null);
    } catch (e) {
      final failure = mapGoogleCalendarFailure(e);
      if (kDebugMode) {
        debugPrint(
          'GoogleCalendarService: delete failed code=${failure.code.name}',
        );
      }
      _setError(failure.message);
      _setLoading(false);
      return CalendarResult.failure(failure);
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

  @override
  void dispose() {
    authService.removeListener(_onAuthChanged);
    super.dispose();
  }
}

@visibleForTesting
CalendarFailure mapGoogleCalendarFailure(Object error) {
  if (error is calendar.DetailedApiRequestError) {
    return switch (error.status) {
      401 => const CalendarFailure(
        CalendarFailureCode.notAuthenticated,
        'Authentication failed. Please sign in again.',
      ),
      403 => const CalendarFailure(
        CalendarFailureCode.permissionDenied,
        'Access denied. Please check calendar permissions.',
      ),
      429 => const CalendarFailure(
        CalendarFailureCode.rateLimited,
        'Too many requests. Please wait and try again.',
      ),
      final status when status != null && status >= 500 =>
        const CalendarFailure(
          CalendarFailureCode.serviceUnavailable,
          'Google Calendar is temporarily unavailable.',
        ),
      _ => const CalendarFailure(
        CalendarFailureCode.unknown,
        'An error occurred. Please try again.',
      ),
    };
  }

  final message = error.toString().toLowerCase();
  if (message.contains('network') || message.contains('socket')) {
    return const CalendarFailure(
      CalendarFailureCode.networkUnavailable,
      'Network error. Please check your connection.',
    );
  }
  return const CalendarFailure(
    CalendarFailureCode.unknown,
    'An error occurred. Please try again.',
  );
}
