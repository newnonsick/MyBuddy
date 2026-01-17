import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/llm/llm_service.dart';
import '../core/memory/memory_service.dart';
import 'model_controller.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.models,
    required this.llm,
    required this.memory,
  });

  final ModelController models;
  final LlmService llm;
  final MemoryService memory;

  final List<Map<String, String>> _conversation = <Map<String, String>>[];

  bool _llmInstalled = false;
  bool get llmInstalled => _llmInstalled;

  bool _installingLlm = false;
  bool get installingLlm => _installingLlm;

  String? _llmError;
  String? get llmError => _llmError;

  static const String _prefHideChatLog = 'hideChatLog';

  bool _hideChatLog = false;
  bool get hideChatLog => _hideChatLog;

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _hideChatLog =
        prefs.getBool(_prefHideChatLog) ??
        false;
    notifyListeners();
  }

  Future<void> setHideChatLog(bool value) async {
    if (value == _hideChatLog) return;
    _hideChatLog = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefHideChatLog, value);
  }

  Future<void> startup() async {
    await loadPreferences();
    await llm.initialize();
    await models.loadLocalState();

    final lastUsedId = models.lastUsedModelId;
    if (lastUsedId != null && lastUsedId.trim().isNotEmpty) {
      final stillInstalled = models.installedModels.any(
        (m) => m.id == lastUsedId,
      );
      if (stillInstalled) {
        models.setPendingSelection(lastUsedId);
        await models.commitSelection();
        await activateSelectedModel();
      }
    }
  }

  Future<void> activateSelectedModel() async {
    if (_installingLlm) return;

    _llmError = null;
    _llmInstalled = false;
    notifyListeners();

    final selected = models.selectedInstalledModel;
    if (selected == null) {
      _llmError = 'No model selected.';
      notifyListeners();
      return;
    }

    _installingLlm = true;
    notifyListeners();

    try {
      await llm.applyConfig(
        modelType: selected.config.toGemmaModelType(),
        maxTokens: selected.config.maxTokens,
        tokenBuffer: selected.config.tokenBuffer,
        temperature: selected.config.temperature,
        randomSeed: selected.config.randomSeed,
        topK: selected.config.topK,
        topP: selected.config.topP,
        isThinking: selected.config.isThinking,
        supportsFunctionCalls: selected.config.supportsFunctionCalls,
        modelFileType: selected.config.fileType,
      );
      await llm.installFromLocalFile(selected.localPath);
      _llmInstalled = true;

      await models.markLastUsedSelected();
    } catch (e) {
      _llmError = 'Model initialization failed: $e';
      _llmInstalled = false;
    } finally {
      _installingLlm = false;
      notifyListeners();
    }
  }

  Future<String> chatOnce(String userText) async {
    final memoryText = await memory.loadMemory();
    final systemPrompt = await memory.buildSystemPrompt(memory: memoryText);

    _conversation.add(<String, String>{'role': 'user', 'text': userText});

    final assistant = await llm.generateChat(
      systemText: systemPrompt,
      userText: userText,
    );

    _conversation.add(<String, String>{'role': 'assistant', 'text': assistant});

    debugPrint('LLM assistant response:\n$assistant');

    unawaited(
      memory.updateMemoryFromConversation(
        conversation: List<Map<String, String>>.unmodifiable(_conversation),
        llm: llm,
      ),
    );

    return assistant;
  }
}
