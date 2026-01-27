import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/llm/llm_service.dart';
import '../core/memory/memory_service.dart';
import '../core/unity/unity_bridge.dart';
import 'app_controller.dart';
import 'model_controller.dart';

final unityBridgeProvider = Provider<UnityBridge>((ref) {
  const channel = MethodChannel('unity_bridge');
  return UnityBridge(channel: channel);
});

final llmServiceProvider = Provider<LlmService>((ref) {
  final unityBridge = ref.watch(unityBridgeProvider);
  return LlmService(unityBridge: unityBridge);
});

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

final modelControllerProvider = ChangeNotifierProvider<ModelController>((ref) {
  return ModelController();
});

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final models = ref.read(modelControllerProvider);
  final llm = ref.read(llmServiceProvider);
  final memory = ref.read(memoryServiceProvider);

  return AppController(models: models, llm: llm, memory: memory);
});
