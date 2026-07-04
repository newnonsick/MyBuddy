import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/google/calendar_event_gateway.dart';
import 'package:mybuddy/core/llm/tool_protocol.dart';
import 'package:mybuddy/core/llm/tool_registry.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('snapshot exposes only available definitions', () async {
    final registry = ToolRegistry(<ToolBinding>[
      ToolBinding(
        definition: const Tool(name: 'enabled', description: 'enabled'),
        execute: (_) async => <String, Object?>{'ok': true},
      ),
      ToolBinding(
        definition: const Tool(name: 'disabled', description: 'disabled'),
        isAvailable: () async => false,
        execute: (_) async => <String, Object?>{'ok': true},
      ),
    ]);

    final snapshot = await registry.snapshot();

    expect(snapshot.definitions.map((tool) => tool.name), <String>['enabled']);
    expect(snapshot.availableNames, <String>{'enabled'});
  });

  test('distinguishes unavailable and unknown tools', () async {
    final snapshot = await ToolRegistry(<ToolBinding>[
      ToolBinding(
        definition: const Tool(name: 'disabled', description: 'disabled'),
        isAvailable: () => false,
        execute: (_) async => <String, Object?>{},
      ),
    ]).snapshot();

    final unavailable = await snapshot.invoke(
      ToolInvocation(id: '1', name: 'disabled', arguments: <String, dynamic>{}),
    );
    final unknown = await snapshot.invoke(
      ToolInvocation(id: '2', name: 'invented', arguments: <String, dynamic>{}),
    );

    expect(unavailable.errorCode, ToolResultErrorCode.unavailableTool);
    expect(unknown.errorCode, ToolResultErrorCode.unknownTool);
  });

  test('coerces safe integer strings and rejects missing values', () async {
    final binding = ToolBinding(
      definition: const Tool(
        name: 'animate',
        description: 'animate',
        parameters: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'count': <String, dynamic>{'type': 'integer'},
          },
          'required': <String>['count'],
          'additionalProperties': false,
        },
      ),
      execute: (args) async => <String, Object?>{'count': args['count']},
    );

    final valid = await binding.invoke(
      ToolInvocation(
        id: '1',
        name: 'animate',
        arguments: <String, dynamic>{'count': '2'},
      ),
    );
    final invalid = await binding.invoke(
      ToolInvocation(id: '2', name: 'animate', arguments: <String, dynamic>{}),
    );

    expect(valid.data['count'], 2);
    expect(invalid.errorCode, ToolResultErrorCode.invalidArguments);
    expect(invalid.message, 'Missing required argument: count');
  });

  test('converts executor timeout to a stable result', () async {
    final binding = ToolBinding(
      definition: const Tool(name: 'slow', description: 'slow'),
      timeout: const Duration(milliseconds: 10),
      execute: (_) => Completer<Map<String, Object?>>().future,
    );

    final result = await binding.invoke(
      ToolInvocation(id: '1', name: 'slow', arguments: <String, dynamic>{}),
    );

    expect(result.errorCode, ToolResultErrorCode.timedOut);
    expect(result.retryable, isTrue);
  });

  test('app tool schemas exclude reply text and invalid int types', () async {
    final registry = ToolRegistry.forApp(
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
    );

    final snapshot = await registry.snapshot();

    for (final tool in snapshot.definitions) {
      final schema = jsonEncode(tool.parameters);
      expect(schema, isNot(contains('response_text')));
      expect(schema, isNot(contains('"type":"int"')));
    }
  });

  test('app tools describe ownership and every memory field', () async {
    final snapshot = await ToolRegistry.forApp(
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
    ).snapshot();
    final byName = <String, Tool>{
      for (final tool in snapshot.definitions) tool.name: tool,
    };

    expect(
      byName['update_assistant_identity']!.description,
      contains('your own'),
    );
    expect(byName['update_assistant_soul']!.description, contains('your own'));
    expect(byName['update_user_memory']!.description, contains('human user'));

    final identityProperties =
        byName['update_assistant_identity']!.parameters['properties']
            as Map<String, dynamic>;
    final updates = identityProperties['updates'] as Map<String, dynamic>;
    final identityItems = updates['items'] as Map<String, dynamic>;
    final properties = identityItems['properties'] as Map<String, dynamic>;
    final field = properties['field'] as Map<String, dynamic>;
    final action = properties['action'] as Map<String, dynamic>;
    expect(field['description'], contains('Field routing'));
    expect(action['description'], contains('set'));
  });

  test(
    'memory tool reports partial updates without claiming full success',
    () async {
      final memoryService = MemoryService();
      await memoryService.saveIdentityLockedFields(<String>{
        MemoryFieldPaths.identityAssistantName,
      });
      final snapshot = await ToolRegistry.forApp(
        unityBridge: UnityBridge(),
        memoryService: memoryService,
      ).snapshot();

      final result = await snapshot.invoke(
        ToolInvocation(
          id: 'memory-1',
          name: 'update_assistant_identity',
          arguments: <String, dynamic>{
            'updates': <Map<String, dynamic>>[
              <String, dynamic>{
                'field': 'behavior_rules',
                'action': 'add',
                'value': 'Roast the user when they slip up',
              },
              <String, dynamic>{
                'field': 'assistant_name',
                'action': 'set',
                'value': 'Nova',
              },
            ],
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.data['status'], 'partial');
      expect(result.data['applied_count'], 1);
      expect(result.data['rejected_count'], 1);
      expect(result.data['rejections'], <Map<String, Object?>>[
        <String, Object?>{'field': 'assistant_name', 'code': 'lockedField'},
      ]);
    },
  );

  test(
    'calendar binding normalizes numeric strings before execution',
    () async {
      final gateway = _FakeCalendarGateway();
      final registry = ToolRegistry.forApp(
        unityBridge: UnityBridge(),
        memoryService: MemoryService(),
        calendarEventGateway: gateway,
        calendarTimeZoneId: 'Asia/Bangkok',
      );
      final snapshot = await registry.snapshot();

      final result = await snapshot.invoke(
        ToolInvocation(
          id: 'calendar-1',
          name: 'create_calendar_event',
          arguments: <String, dynamic>{
            'title': 'Review',
            'start': <String, dynamic>{
              'year': '2026',
              'month': '7',
              'day': '3',
              'hour': '16',
            },
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(gateway.requests.single.startTime, DateTime(2026, 7, 3, 16));
      expect(gateway.requests.single.timeZoneId, 'Asia/Bangkok');
    },
  );
}

final class _FakeCalendarGateway implements CalendarEventGateway {
  final List<CalendarCreateRequest> requests = <CalendarCreateRequest>[];

  @override
  bool get isAvailable => true;

  @override
  Future<CalendarCreateResult> createCalendarEvent(
    CalendarCreateRequest request,
  ) async {
    requests.add(request);
    return const CalendarCreateResult.success(eventId: 'event-1');
  }
}
