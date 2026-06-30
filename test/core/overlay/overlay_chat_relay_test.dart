import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/app/app_controller.dart';
import 'package:mybuddy/app/model_controller.dart';
import 'package:mybuddy/core/llm/llm_service.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:mybuddy/core/model/model_descriptor.dart';
import 'package:mybuddy/core/model/model_store.dart';
import 'package:mybuddy/core/overlay/overlay_chat_relay.dart';
import 'package:mybuddy/core/stt/stt_service.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/fakes/fake_llm_platform.dart';

class FakeAppController extends AppController {
  FakeAppController({
    required super.models,
    required super.llm,
    required super.memory,
  });

  int chatCount = 0;
  Completer<String>? chatCompleter;
  bool _fakeLlmInstalled = false;

  @override
  bool get llmInstalled => _fakeLlmInstalled;

  void setLlmInstalled(bool installed) {
    _fakeLlmInstalled = installed;
    notifyListeners();
  }

  @override
  Future<String> chatOnce(String userText) async {
    chatCount++;
    final completer = chatCompleter ?? Completer<String>();
    if (chatCompleter == null) {
      completer.complete('Response: $userText');
    }
    return completer.future;
  }
}

class FakeSttService extends SttService {
  const FakeSttService();
}

class FakeModelStore extends ModelStore {
  List<InstalledModel> fakeInstalled = [];

  @override
  Future<List<InstalledModel>> listInstalled() async {
    return fakeInstalled;
  }

  @override
  Future<String> resolveLocalPath(String fileName) async {
    return fileName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAppController appController;
  late FakeSttService sttService;
  late OverlayChatRelay relay;
  final List<dynamic> sentMessages = [];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fakePlatform = FakeLlmPlatform();
    final llmService = LlmService(
      platform: fakePlatform,
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
    );
    final fakeStore = FakeModelStore();
    final modelController = ModelController(store: fakeStore);
    appController = FakeAppController(
      models: modelController,
      llm: llmService,
      memory: MemoryService(),
    );
    sttService = const FakeSttService();
    relay = OverlayChatRelay(
      appController: appController,
      sttService: sttService,
    );
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
    relay.dispose();
    const channel = BasicMessageChannel<dynamic>(
      'x-slayer/overlay_messenger',
      JSONMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler(channel, null);
  });

  test('relay broadcasts status on start and when app state changes', () async {
    relay.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Check initial broadcast
    expect(sentMessages.length, 1);
    var status = jsonDecode(sentMessages[0]) as Map;
    expect(status['type'], 'runtime_status');
    expect(status['llmInstalled'], false);

    // Update app state and check subsequent broadcast
    appController.setLlmInstalled(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(sentMessages.length, 2);
    status = jsonDecode(sentMessages[1]) as Map;
    expect(status['type'], 'runtime_status');
    expect(status['llmInstalled'], true);
  });

  test('relay routes chat_request to app and sends response back', () async {
    appController.setLlmInstalled(true);
    relay.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sentMessages.clear();

    final payload = {
      'type': 'chat_request',
      'text': 'Hello MyBuddy',
      'requestId': 'req-123',
    };

    // Send chat request to relay message handler
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'x-slayer/overlay_messenger',
          const JSONMessageCodec().encodeMessage(payload),
          (_) {},
        );

    // Wait for async processing
    await Future<void>.delayed(Duration.zero);

    expect(appController.chatCount, 1);
    expect(sentMessages.length, 1);
    final responseMsg = sentMessages.firstWhere((m) {
      final map = jsonDecode(m) as Map;
      return map['type'] == 'chat_response';
    });
    final response = jsonDecode(responseMsg) as Map;
    expect(response['requestId'], 'req-123');
    expect(response['reply'], 'Response: Hello MyBuddy');
  });

  test(
    'relay deduplicates duplicate chat_requests with the same requestId',
    () async {
      appController.setLlmInstalled(true);
      appController.chatCompleter = Completer<String>();
      relay.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      sentMessages.clear();

      final payload = {
        'type': 'chat_request',
        'text': 'Hello MyBuddy',
        'requestId': 'dup-123',
      };

      // Send first chat request
      final f1 = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            'x-slayer/overlay_messenger',
            const JSONMessageCodec().encodeMessage(payload),
            (_) {},
          );

      // Send second duplicate request immediately
      final f2 = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            'x-slayer/overlay_messenger',
            const JSONMessageCodec().encodeMessage(payload),
            (_) {},
          );

      // Complete the in-flight chat after a brief delay to avoid deadlock
      Timer(const Duration(milliseconds: 50), () {
        appController.chatCompleter!.complete('Response: Hello MyBuddy');
      });

      await Future.wait([f1, f2]);
      await Future<void>.delayed(Duration.zero);

      expect(appController.chatCount, 1);

      // Should only have received one chat_response
      final responses = sentMessages.where((m) {
        final map = jsonDecode(m) as Map;
        return map['type'] == 'chat_response';
      }).toList();
      expect(responses.length, 1);
    },
  );
}
