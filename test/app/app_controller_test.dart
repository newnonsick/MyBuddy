import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/app/app_controller.dart';
import 'package:mybuddy/app/model_controller.dart';
import 'package:mybuddy/core/llm/llm_service.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:mybuddy/core/model/model_descriptor.dart';
import 'package:mybuddy/core/model/model_store.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/llm/fakes/fake_llm_platform.dart';

// A mock memory service that can throw errors to test exception safety
class FakeMemoryService extends MemoryService {
  bool throwOnLoad = false;

  @override
  Future<UserMemory> loadMemoryData() async {
    if (throwOnLoad) {
      throw Exception('Fake loadMemoryData error');
    }
    return super.loadMemoryData();
  }
}

// A fake ModelStore that bypasses path_provider and file existence checks
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

  late FakeLlmPlatform fakePlatform;
  late LlmService llmService;
  late FakeMemoryService memoryService;
  late FakeModelStore fakeStore;
  late ModelController modelController;
  late AppController appController;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fakePlatform = FakeLlmPlatform();
    llmService = LlmService(
      platform: fakePlatform,
      unityBridge: UnityBridge(),
      memoryService: MemoryService(),
    );
    memoryService = FakeMemoryService();
    fakeStore = FakeModelStore();
    modelController = ModelController(store: fakeStore);
    appController = AppController(
      models: modelController,
      llm: llmService,
      memory: memoryService,
    );
  });

  test('busy state is cleared when memory loading fails', () async {
    memoryService.throwOnLoad = true;

    await expectLater(
      appController.chatOnce('hello'),
      throwsA(isA<Exception>()),
    );

    expect(appController.generatingResponse, false);
  });

  test('concurrent activations are deduplicated and share Future', () async {
    // Populate an installed model in fake store
    const descriptor = InstalledModel(
      id: 'test_model',
      fileName: 'test_model.bin',
      localPath: 'test_model.bin',
      expectedMinBytes: 1000,
      config: LlmModelConfig(
        type: 'gemma_2b_it',
        maxTokens: 2048,
        tokenBuffer: 256,
        randomSeed: 42,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        isThinking: false,
        supportsFunctionCalls: false,
        fileType: ModelFileType.task,
      ),
      downloadedBytes: 1000,
      downloadedAtIso: '2026-06-30T00:00:00.000',
    );
    fakeStore.fakeInstalled = [descriptor];

    // Set model in controller
    modelController.setPendingSelection('test_model');
    // Stub selectedInstalledModel (since ModelController uses ModelSelectionService which reads from prefs)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mybuddy.selected_model_id.v1', 'test_model');

    // Reload model list in ModelController
    await modelController.loadLocalState();

    // Call activateSelectedModel twice concurrently
    final f1 = appController.activateSelectedModel();
    final f2 = appController.activateSelectedModel();

    expect(identical(f1, f2), true); // Both callers get the exact same Future
    await Future.wait([f1, f2]);

    expect(fakePlatform.activateCount, 1); // Native activation called only once
  });

  test('same selected model activation is idempotent after success', () async {
    const descriptor = InstalledModel(
      id: 'test_model',
      fileName: 'test_model.bin',
      localPath: 'test_model.bin',
      expectedMinBytes: 1000,
      config: LlmModelConfig(
        type: 'gemma_2b_it',
        maxTokens: 2048,
        tokenBuffer: 256,
        randomSeed: 42,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        isThinking: false,
        supportsFunctionCalls: false,
        fileType: ModelFileType.task,
      ),
      downloadedBytes: 1000,
      downloadedAtIso: '2026-06-30T00:00:00.000',
    );
    fakeStore.fakeInstalled = [descriptor];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mybuddy.selected_model_id.v1', 'test_model');
    await modelController.loadLocalState();

    await appController.activateSelectedModel();
    await appController.activateSelectedModel();

    expect(fakePlatform.activateCount, 1);
    expect(fakePlatform.getActiveModelCount, 1);
  });
}
