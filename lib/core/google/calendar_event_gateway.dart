enum CalendarFailureCode {
  notAuthenticated,
  permissionDenied,
  rateLimited,
  networkUnavailable,
  serviceUnavailable,
  unknown;

  bool get isRetryable => switch (this) {
    rateLimited || networkUnavailable || serviceUnavailable => true,
    _ => false,
  };
}

final class CalendarFailure {
  const CalendarFailure(this.code, this.message);

  final CalendarFailureCode code;
  final String message;

  bool get isRetryable => code.isRetryable;
}

final class CalendarCreateRequest {
  const CalendarCreateRequest({
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.timeZoneId,
    this.description,
    this.location,
  });

  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String timeZoneId;
  final String? location;
}

final class CalendarCreateResult {
  const CalendarCreateResult.success({this.eventId}) : failure = null;
  const CalendarCreateResult.failure(this.failure) : eventId = null;

  final String? eventId;
  final CalendarFailure? failure;

  bool get isSuccess => failure == null;
}

abstract interface class CalendarEventGateway {
  bool get isAvailable;

  Future<CalendarCreateResult> createCalendarEvent(
    CalendarCreateRequest request,
  );
}
