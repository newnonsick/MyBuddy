import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/llm_service.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_llm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmPlatform fakePlatform;
  late LlmService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fakePlatform = FakeLlmPlatform();
    service = LlmService(
      platform: fakePlatform,
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
    );
  });

  test('concurrent model activation creates one model', () async {
    await Future.wait([
      service.installFromLocalFile('model.bin'),
      service.installFromLocalFile('model.bin'),
    ]);

    expect(fakePlatform.activateCount, 1);
    expect(fakePlatform.getActiveModelCount, 1);
  });

  test('app operations are serialized', () async {
    fakePlatform.generationCompleter = Completer<void>();

    // Start a generateText which will be paused
    final future1 = service.generateText('hello 1');

    // Start another generateText
    final future2 = service.generateText('hello 2');

    // Since they must be serialized, the second one should not have started (its query should not be accepted yet)
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fakePlatform.acceptedQueries, ['hello 1']);

    // Complete the first one
    fakePlatform.generationCompleter!.complete();
    fakePlatform.generationCompleter = null;

    await Future.wait([future1, future2]);

    expect(fakePlatform.acceptedQueries, ['hello 1', 'hello 2']);
  });

  test('stable session is reused across turns', () async {
    await service.generateChat(systemText: 'system_inst', userText: 'hello 1');
    await service.generateChat(systemText: 'system_inst', userText: 'hello 2');

    expect(fakePlatform.createChatCount, 1);
    expect(fakePlatform.createSessionCount, 1);
  });

  test('pre-acceptance failure retries once', () async {
    fakePlatform.failNextAddQuery = true;
    await service.generateChat(systemText: 'stable', userText: 'hello');

    expect(
      fakePlatform.acceptedQueries.where((q) => q == 'hello'),
      hasLength(1),
    );
  });

  test('post-acceptance failure never resends', () async {
    fakePlatform.failAfterAccept = true;

    await expectLater(
      service.generateChat(systemText: 'stable', userText: 'hello'),
      throwsA(
        isA<Exception>(),
      ), // In Task 3, it should throw a LlmRuntimeException or similar Exception
    );

    expect(
      fakePlatform.acceptedQueries.where((q) => q == 'hello'),
      hasLength(1),
    );
  });

  test('memory restoration restores a usable chat session', () async {
    // Send one chat turn
    await service.generateChat(systemText: 'sys', userText: 'chat turn 1');

    // Run extractUserMemoryFromChat
    final memory = await service.extractUserMemoryFromChat('{}');
    expect(memory, 'fake response chunk');

    // Memory extraction uses a temporary one-shot session and does not close or
    // recreate the active chat session.
    expect(fakePlatform.closeSessionCount, 1);
    expect(fakePlatform.createChatCount, 1);

    // Send another turn
    final reply2 = await service.generateChat(
      systemText: 'sys',
      userText: 'chat turn 2',
    );
    expect(reply2, 'fake response chunk');
  });

  test('memory extraction cannot overlap chat generation', () async {
    // Pre-populate dialogue so extractUserMemoryFromChat does not return early
    await service.generateChat(systemText: 'sys', userText: 'chat turn 1');
    expect(fakePlatform.createSessionCount, 1);

    fakePlatform.generationCompleter = Completer<void>();

    // Start generating chat (paused)
    final chatFuture = service.generateChat(
      systemText: 'sys',
      userText: 'chat 2',
    );

    // Try to trigger memory extraction
    final memoryFuture = service.extractUserMemoryFromChat('{}');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    // Memory extraction should not have started (its session count is still 1)
    expect(fakePlatform.createSessionCount, 1);

    // Complete chat generation
    fakePlatform.generationCompleter!.complete();
    fakePlatform.generationCompleter = null;

    await Future.wait([chatFuture, memoryFuture]);

    // 1 (chat session) + 1 (queued temp extraction session).
    expect(fakePlatform.createSessionCount, 2);
  });

  test('qwen special tool-call text is executed instead of shown', () async {
    service = LlmService(
      platform: fakePlatform,
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
      modelType: ModelType.qwen,
      supportsFunctionCalls: true,
    );
    fakePlatform.asyncResponseBatches.add([
      '<|tool_call|>call:update_user_memory{response_text:<escape>Memory queued.<escape>}<|/tool_call|>',
    ]);

    final reply = await service.generateChat(
      systemText: 'system',
      userText: 'remember this',
    );

    expect(reply, 'Memory queued.');
    expect(reply, isNot(contains('<|tool_call')));
  });

  test('memory tool call applies patch without extraction session', () async {
    final memoryService = MemoryService();
    service = LlmService(
      platform: fakePlatform,
      unityBridge: UnityBridge(),
      memoryService: memoryService,
      modelType: ModelType.qwen,
      supportsFunctionCalls: true,
    );
    fakePlatform.asyncResponseBatches.add([
      '{"name":"update_user_memory","parameters":{"response_text":"I will remember that.","updates":[{"field":"preferences","action":"add","value":"prefers concise answers"}]}}',
    ]);

    final reply = await service.generateChat(
      systemText: 'system',
      userText: 'remember I prefer concise answers',
    );

    final memory = await memoryService.loadMemoryData();
    expect(reply, 'I will remember that.');
    expect(memory.user.preferences, contains('prefers concise answers'));
    expect(fakePlatform.createSessionCount, 1);
  });

  test(
    'raw tool-call text is handled even when native tools are disabled',
    () async {
      const unityChannel = MethodChannel('unity_bridge_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(unityChannel, (_) async => null);

      service = LlmService(
        platform: fakePlatform,
        unityBridge: UnityBridge(channel: unityChannel),
        memoryService: MemoryService(),
        modelType: ModelType.qwen,
        supportsFunctionCalls: false,
      );
      fakePlatform.asyncResponseBatches.add([
        '<|tool_call>call:function_avatar_action{animation:<|"|>think<|"|>,animate_count:1,response_text_text:<|"|>I can certainly help you with that. I\'ll make a reminder for you to grab milk on your way home tonight. Is there anything else I can assist you with right now?<|"|>}<tool_call|>',
      ]);
      fakePlatform.asyncResponseBatches.add(['clean next response']);

      final reply = await service.generateChat(
        systemText: 'system',
        userText: 'remember this too',
      );

      expect(
        reply,
        'I can certainly help you with that. I\'ll make a reminder for you to grab milk on your way home tonight. Is there anything else I can assist you with right now?',
      );
      expect(reply, isNot(contains('<|tool_call')));

      final next = await service.generateChat(
        systemText: 'system',
        userText: 'next turn',
      );
      expect(next, 'clean next response');
      expect(fakePlatform.createChatCount, 2);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(unityChannel, null);
    },
  );

  test(
    'json parameters tool call is handled when native tools are disabled',
    () async {
      const unityChannel = MethodChannel('unity_bridge_json_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(unityChannel, (_) async => null);

      service = LlmService(
        platform: fakePlatform,
        unityBridge: UnityBridge(channel: unityChannel),
        memoryService: MemoryService(),
        modelType: ModelType.qwen,
        supportsFunctionCalls: false,
      );
      fakePlatform.asyncResponseBatches.add([
        '{"name":"perform_avatar_action","parameters":{"animation":"think","animate_count":1,"response_text":"JSON handled."}}',
      ]);

      final reply = await service.generateChat(
        systemText: 'system',
        userText: 'use json tool format',
      );

      expect(reply, 'JSON handled.');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(unityChannel, null);
    },
  );
}
