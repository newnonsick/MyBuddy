import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/tool_protocol.dart';

void main() {
  test('canonical signature ignores map insertion order', () {
    final first = ToolInvocation(
      id: 'run-1-r1-c1',
      name: 'create_calendar_event',
      arguments: <String, dynamic>{
        'title': 'Review',
        'start_date': '2026-07-01',
      },
    );
    final second = ToolInvocation(
      id: 'run-1-r1-c2',
      name: 'create_calendar_event',
      arguments: <String, dynamic>{
        'start_date': '2026-07-01',
        'title': 'Review',
      },
    );

    expect(first.canonicalSignature, second.canonicalSignature);
  });

  test('tool result emits a correlated model payload', () {
    const result = ToolExecutionResult.success(
      id: 'run-1-r1-c1',
      name: 'perform_avatar_action',
      data: <String, Object?>{'animation': 'greet'},
    );

    expect(result.toModelJson(), <String, Object?>{
      'call_id': 'run-1-r1-c1',
      'name': 'perform_avatar_action',
      'status': 'success',
      'data': <String, Object?>{'animation': 'greet'},
    });
  });

  test('duplicate result preserves outcome under a new call id', () {
    const result = ToolExecutionResult.failure(
      id: 'first',
      name: 'calendar',
      code: ToolResultErrorCode.executionFailed,
      message: 'Calendar failed.',
      retryable: true,
    );

    final duplicate = result.copyForDuplicate(id: 'second');

    expect(duplicate.id, 'second');
    expect(duplicate.cached, isTrue);
    expect(duplicate.errorCode, ToolResultErrorCode.executionFailed);
    expect(duplicate.retryable, isTrue);
  });
}
