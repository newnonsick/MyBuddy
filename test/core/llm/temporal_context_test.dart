import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/temporal_context.dart';

void main() {
  test('serializes app-owned local time and offset', () {
    final context = TemporalContext(
      localNow: DateTime(2026, 7, 2, 14, 5, 6),
      timeZoneId: 'Asia/Bangkok',
      utcOffset: const Duration(hours: 7),
    );

    expect(
      context.toPromptBlock(),
      '<runtime_context>{"current_local_datetime":'
      '"2026-07-02T14:05:06.000","timezone":"Asia/Bangkok",'
      '"utc_offset":"+07:00"}</runtime_context>',
    );
  });

  test('formats negative offsets', () {
    final context = TemporalContext(
      localNow: DateTime(2026, 7, 2, 8),
      timeZoneId: 'America/St_Johns',
      utcOffset: const Duration(hours: -3, minutes: -30),
    );

    expect(context.toPromptBlock(), contains('"utc_offset":"-03:30"'));
  });
}
