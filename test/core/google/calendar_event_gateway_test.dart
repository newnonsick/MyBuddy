import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:mybuddy/core/google/calendar_event_gateway.dart';
import 'package:mybuddy/core/google/google_calendar_service.dart';

void main() {
  test('only transient calendar failures are retryable', () {
    expect(CalendarFailureCode.notAuthenticated.isRetryable, isFalse);
    expect(CalendarFailureCode.permissionDenied.isRetryable, isFalse);
    expect(CalendarFailureCode.rateLimited.isRetryable, isTrue);
    expect(CalendarFailureCode.networkUnavailable.isRetryable, isTrue);
    expect(CalendarFailureCode.serviceUnavailable.isRetryable, isTrue);
    expect(CalendarFailureCode.unknown.isRetryable, isFalse);
  });

  test('maps Google status codes to stable failures', () {
    expect(
      mapGoogleCalendarFailure(
        calendar.DetailedApiRequestError(401, 'private'),
      ).code,
      CalendarFailureCode.notAuthenticated,
    );
    expect(
      mapGoogleCalendarFailure(
        calendar.DetailedApiRequestError(403, 'private'),
      ).code,
      CalendarFailureCode.permissionDenied,
    );
    expect(
      mapGoogleCalendarFailure(
        calendar.DetailedApiRequestError(429, 'private'),
      ).code,
      CalendarFailureCode.rateLimited,
    );
    expect(
      mapGoogleCalendarFailure(
        calendar.DetailedApiRequestError(503, 'private'),
      ).code,
      CalendarFailureCode.serviceUnavailable,
    );
  });

  test('maps transport errors without exposing raw text', () {
    final failure = mapGoogleCalendarFailure(
      Exception('SocketException: host and token details'),
    );

    expect(failure.code, CalendarFailureCode.networkUnavailable);
    expect(failure.message, 'Network error. Please check your connection.');
    expect(failure.message, isNot(contains('token')));
  });
}
