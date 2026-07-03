import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/google/calendar_event_gateway.dart';
import 'package:mybuddy/core/llm/calendar_event_tool.dart';
import 'package:mybuddy/core/llm/tool_protocol.dart';

void main() {
  group('calendar event arguments', () {
    test('timed start defaults minute and one-hour end', () {
      final value = CalendarEventTool.parseArguments(<String, dynamic>{
        'title': 'Review',
        'start': <String, dynamic>{
          'year': 2026,
          'month': 7,
          'day': 3,
          'hour': 16,
        },
      });

      expect(value.isAllDay, isFalse);
      expect(value.start, DateTime(2026, 7, 3, 16));
      expect(value.end, DateTime(2026, 7, 3, 17));
    });

    test('date-only start becomes an exclusive one-day event', () {
      final value = CalendarEventTool.parseArguments(<String, dynamic>{
        'title': 'Holiday',
        'start': <String, dynamic>{'year': 2028, 'month': 2, 'day': 29},
      });

      expect(value.isAllDay, isTrue);
      expect(value.start, DateTime(2028, 2, 29));
      expect(value.end, DateTime(2028, 3, 1));
    });

    test('rejects impossible dates', () {
      expect(
        () => CalendarEventTool.parseArguments(<String, dynamic>{
          'title': 'Invalid',
          'start': <String, dynamic>{'year': 2026, 'month': 2, 'day': 30},
        }),
        throwsA(
          isA<ToolArgumentException>().having(
            (error) => error.message,
            'message',
            'Invalid argument: start',
          ),
        ),
      );
    });

    test('rejects minute without hour', () {
      expect(
        () => CalendarEventTool.parseArguments(<String, dynamic>{
          'title': 'Invalid',
          'start': <String, dynamic>{
            'year': 2026,
            'month': 7,
            'day': 3,
            'minute': 30,
          },
        }),
        throwsA(
          isA<ToolArgumentException>().having(
            (error) => error.message,
            'message',
            'Invalid argument: start.minute requires start.hour',
          ),
        ),
      );
    });

    test('rejects out-of-range components', () {
      for (final entry in <String, int>{
        'year': 2101,
        'month': 13,
        'hour': 24,
        'minute': 60,
      }.entries) {
        final start = <String, dynamic>{
          'year': 2026,
          'month': 7,
          'day': 3,
          'hour': 16,
          'minute': 0,
          entry.key: entry.value,
        };

        expect(
          () => CalendarEventTool.parseArguments(<String, dynamic>{
            'title': 'Invalid',
            'start': start,
          }),
          throwsA(isA<ToolArgumentException>()),
          reason: entry.key,
        );
      }
    });

    test('requires matching kinds and increasing end', () {
      expect(
        () => CalendarEventTool.parseArguments(<String, dynamic>{
          'title': 'Invalid',
          'start': <String, dynamic>{
            'year': 2026,
            'month': 7,
            'day': 3,
            'hour': 16,
          },
          'end': <String, dynamic>{'year': 2026, 'month': 7, 'day': 4},
        }),
        throwsA(isA<ToolArgumentException>()),
      );
      expect(
        () => CalendarEventTool.parseArguments(<String, dynamic>{
          'title': 'Invalid',
          'start': <String, dynamic>{
            'year': 2026,
            'month': 7,
            'day': 3,
            'hour': 16,
          },
          'end': <String, dynamic>{
            'year': 2026,
            'month': 7,
            'day': 3,
            'hour': 16,
          },
        }),
        throwsA(isA<ToolArgumentException>()),
      );
    });
  });

  test('definition exposes only numeric calendar components', () {
    final properties =
        CalendarEventTool.definition.parameters['properties']
            as Map<String, dynamic>;
    final start = properties['start'] as Map<String, dynamic>;
    final startProperties = start['properties'] as Map<String, dynamic>;

    expect(properties.keys, <String>{
      'title',
      'description',
      'start',
      'end',
      'location',
    });
    expect(startProperties['year'], containsPair('type', 'integer'));
    expect(startProperties['hour'], containsPair('type', 'integer'));
    expect(properties, isNot(contains('start_date')));
    expect(properties, isNot(contains('end_date')));
    expect(properties, isNot(contains('is_all_day')));
  });

  test('execution sends typed local values and fixed timezone', () async {
    final gateway = _FakeCalendarGateway(
      const CalendarCreateResult.success(eventId: 'event-1'),
    );

    final result = await CalendarEventTool.execute(gateway, <String, dynamic>{
      'title': 'Review',
      'start': <String, dynamic>{
        'year': 2026,
        'month': 7,
        'day': 3,
        'hour': 16,
      },
    }, timeZoneId: 'Asia/Bangkok');

    expect(gateway.requests.single.startTime, DateTime(2026, 7, 3, 16));
    expect(gateway.requests.single.endTime, DateTime(2026, 7, 3, 17));
    expect(gateway.requests.single.timeZoneId, 'Asia/Bangkok');
    expect(result['event_id'], 'event-1');
    expect(result['start_local'], '2026-07-03T16:00:00.000');
  });

  test('execution preserves provider retryability', () async {
    final permissionGateway = _FakeCalendarGateway(
      const CalendarCreateResult.failure(
        CalendarFailure(
          CalendarFailureCode.permissionDenied,
          'Calendar permission denied.',
        ),
      ),
    );
    final rateGateway = _FakeCalendarGateway(
      const CalendarCreateResult.failure(
        CalendarFailure(
          CalendarFailureCode.rateLimited,
          'Calendar rate limited.',
        ),
      ),
    );

    await expectLater(
      CalendarEventTool.execute(
        permissionGateway,
        _timedArguments(),
        timeZoneId: 'Asia/Bangkok',
      ),
      throwsA(
        isA<ToolExecutionException>().having(
          (error) => error.retryable,
          'retryable',
          isFalse,
        ),
      ),
    );
    await expectLater(
      CalendarEventTool.execute(
        rateGateway,
        _timedArguments(),
        timeZoneId: 'Asia/Bangkok',
      ),
      throwsA(
        isA<ToolExecutionException>().having(
          (error) => error.retryable,
          'retryable',
          isTrue,
        ),
      ),
    );
  });
}

Map<String, dynamic> _timedArguments() => <String, dynamic>{
  'title': 'Review',
  'start': <String, dynamic>{'year': 2026, 'month': 7, 'day': 3, 'hour': 16},
};

final class _FakeCalendarGateway implements CalendarEventGateway {
  _FakeCalendarGateway(this.result);

  final CalendarCreateResult result;
  final List<CalendarCreateRequest> requests = <CalendarCreateRequest>[];

  @override
  bool get isAvailable => true;

  @override
  Future<CalendarCreateResult> createCalendarEvent(
    CalendarCreateRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}
