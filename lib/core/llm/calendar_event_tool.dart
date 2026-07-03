import 'package:flutter_gemma/flutter_gemma.dart';

import '../google/calendar_event_gateway.dart';
import 'tool_protocol.dart';

final class LocalDateTimeInput {
  const LocalDateTimeInput._({required this.value, required this.isDateOnly});

  static const minYear = 1900;
  static const maxYear = 2100;

  final DateTime value;
  final bool isDateOnly;

  static LocalDateTimeInput fromMap(Map<String, dynamic> input, String path) {
    final year = input['year'] as int;
    final month = input['month'] as int;
    final day = input['day'] as int;
    final hour = input['hour'] as int?;
    final minute = input['minute'] as int?;

    _requireRange(year, minYear, maxYear, '$path.year');
    _requireRange(month, 1, 12, '$path.month');
    if (hour != null) _requireRange(hour, 0, 23, '$path.hour');
    if (minute != null) _requireRange(minute, 0, 59, '$path.minute');
    if (minute != null && hour == null) {
      throw ToolArgumentException(
        'Invalid argument: $path.minute requires $path.hour',
      );
    }

    final value = DateTime(year, month, day, hour ?? 0, minute ?? 0);
    if (value.year != year ||
        value.month != month ||
        value.day != day ||
        value.hour != (hour ?? 0) ||
        value.minute != (minute ?? 0)) {
      throw ToolArgumentException('Invalid argument: $path');
    }
    return LocalDateTimeInput._(value: value, isDateOnly: hour == null);
  }

  static void _requireRange(int value, int min, int max, String path) {
    if (value < min || value > max) {
      throw ToolArgumentException(
        'Invalid argument: $path must be between $min and $max',
      );
    }
  }
}

final class CreateCalendarEventArguments {
  const CreateCalendarEventArguments({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    this.description,
    this.location,
  });

  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? location;
}

abstract final class CalendarEventTool {
  static const definition = Tool(
    name: 'create_calendar_event',
    description:
        'Create a Google Calendar event. Infer a concise title and date/time '
        'from the request and runtime context. A start without hour is all-day. '
        'Timed example parameters: {"title":"Review","start":{"year":2026,'
        '"month":7,"day":3,"hour":16,"minute":0}}. All-day example '
        'parameters: {"title":"Holiday","start":{"year":2026,"month":7,'
        '"day":3}}.',
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'title': <String, dynamic>{
          'type': 'string',
          'description': 'Concise event title inferred from the request.',
        },
        'description': <String, dynamic>{'type': 'string'},
        'start': _dateTimeParameters,
        'end': _dateTimeParameters,
        'location': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['title', 'start'],
      'additionalProperties': false,
    },
  );

  static const _dateTimeParameters = <String, dynamic>{
    'type': 'object',
    'description':
        'Local calendar components. Omit hour for all-day; minute defaults to 0.',
    'properties': <String, dynamic>{
      'year': <String, dynamic>{'type': 'integer'},
      'month': <String, dynamic>{'type': 'integer'},
      'day': <String, dynamic>{'type': 'integer'},
      'hour': <String, dynamic>{'type': 'integer'},
      'minute': <String, dynamic>{'type': 'integer'},
    },
    'required': <String>['year', 'month', 'day'],
    'additionalProperties': false,
  };

  static CreateCalendarEventArguments parseArguments(
    Map<String, dynamic> arguments,
  ) {
    final title = (arguments['title'] as String).trim();
    if (title.isEmpty) {
      throw const ToolArgumentException('Invalid argument: title');
    }

    final startInput = _dateInput(arguments['start'], 'start');
    final endValue = arguments['end'];
    final endInput = endValue == null ? null : _dateInput(endValue, 'end');
    if (endInput != null && endInput.isDateOnly != startInput.isDateOnly) {
      throw const ToolArgumentException(
        'Invalid argument: start and end must both be date-only or timed',
      );
    }

    final start = startInput.value;
    final end = endInput?.value ?? _defaultEnd(startInput);
    if (!end.isAfter(start)) {
      throw const ToolArgumentException(
        'Invalid argument: end must be later than start',
      );
    }
    return CreateCalendarEventArguments(
      title: title,
      description: arguments['description'] as String?,
      start: start,
      end: end,
      isAllDay: startInput.isDateOnly,
      location: arguments['location'] as String?,
    );
  }

  static LocalDateTimeInput _dateInput(Object? value, String path) {
    if (value is! Map) {
      throw ToolArgumentException('Invalid argument: $path');
    }
    return LocalDateTimeInput.fromMap(
      value.map((key, item) => MapEntry(key.toString(), item)),
      path,
    );
  }

  static DateTime _defaultEnd(LocalDateTimeInput start) {
    final value = start.value;
    if (!start.isDateOnly) return value.add(const Duration(hours: 1));
    return DateTime(value.year, value.month, value.day + 1);
  }

  static Future<Map<String, Object?>> execute(
    CalendarEventGateway gateway,
    Map<String, dynamic> arguments, {
    required String timeZoneId,
  }) async {
    final value = parseArguments(arguments);
    final result = await gateway.createCalendarEvent(
      CalendarCreateRequest(
        title: value.title,
        description: value.description,
        startTime: value.start,
        endTime: value.end,
        isAllDay: value.isAllDay,
        timeZoneId: timeZoneId,
        location: value.location,
      ),
    );
    final failure = result.failure;
    if (failure != null) {
      throw ToolExecutionException(
        failure.message,
        retryable: failure.isRetryable,
      );
    }
    return <String, Object?>{
      'event_id': result.eventId,
      'title': value.title,
      'start_local': value.start.toIso8601String(),
      'end_local': value.end.toIso8601String(),
      'is_all_day': value.isAllDay,
    };
  }
}
