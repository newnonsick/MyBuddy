import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/app/model_controller.dart';
import 'package:mybuddy/core/overlay/overlay_app_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ModelController modelController;
  late OverlayAppProxy proxy;
  late StreamController<dynamic> streamController;
  final List<dynamic> sentMessages = [];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    modelController = ModelController();
    proxy = OverlayAppProxy(models: modelController);
    streamController = StreamController<dynamic>.broadcast();
    proxy.startListening(streamController.stream);
    sentMessages.clear();

    // Register a mock handler on x-slayer/overlay_messenger basic message channel via BinaryMessenger
    const channel = BasicMessageChannel<dynamic>(
      'x-slayer/overlay_messenger',
      JSONMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler(channel, (message) async {
          sentMessages.add(message);
          return null;
        });
  });

  tearDown(() {
    proxy.disposeRelay();
    streamController.close();
    const channel = BasicMessageChannel<dynamic>(
      'x-slayer/overlay_messenger',
      JSONMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler(channel, null);
  });

  test(
    'updates runtime status state when status payload is received',
    () async {
      expect(proxy.llmInstalled, false);
      expect(proxy.generatingResponse, false);
      expect(proxy.conversation.isEmpty, true);

      streamController.add({
        'type': 'runtime_status',
        'llmInstalled': true,
        'installingLlm': false,
        'llmError': 'none',
        'generatingResponse': true,
        'transcribingAudio': false,
        'conversation': [
          {'role': 'user', 'text': 'hello'},
          {'role': 'assistant', 'text': 'hi there'},
        ],
      });

      // Wait a brief tick for stream listener microtask
      await Future<void>.delayed(Duration.zero);

      expect(proxy.llmInstalled, true);
      expect(proxy.generatingResponse, true);
      expect(proxy.conversation.length, 2);
      expect(proxy.conversation[0]['role'], 'user');
      expect(proxy.conversation[0]['text'], 'hello');
    },
  );

  test(
    'chatOnce sends chat_request and completes when reply payload arrives',
    () async {
      // Simulate chat response via incoming stream after request is sent
      Timer(const Duration(milliseconds: 100), () {
        expect(sentMessages.length, 1);
        final raw = sentMessages.first;
        final req = raw is String ? jsonDecode(raw) as Map : raw as Map;
        expect(req['type'], 'chat_request');
        expect(req['text'], 'Who are you?');
        final requestId = req['requestId'];

        streamController.add({
          'type': 'chat_response',
          'requestId': requestId,
          'reply': 'I am MyBuddy',
        });
      });

      final reply = await proxy.chatOnce('Who are you?');
      expect(reply, 'I am MyBuddy');
    },
  );

  test('switchModel sends model_switch_request', () async {
    Timer(const Duration(milliseconds: 100), () {
      expect(sentMessages.length, 1);
      final raw = sentMessages.first;
      final req = raw is String ? jsonDecode(raw) as Map : raw as Map;
      expect(req['type'], 'model_switch_request');
      expect(req['modelId'], 'gemma_v2');
      final requestId = req['requestId'];

      streamController.add({
        'type': 'model_switch_response',
        'requestId': requestId,
      });
    });

    await proxy.switchModel('gemma_v2');
  });
}
