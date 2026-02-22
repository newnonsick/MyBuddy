import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/llm/llm_service.dart';
import '../core/memory/memory_service.dart';
import 'model_controller.dart';

abstract final class AppPreferenceKeys {
  static const String hideChatLog = 'hideChatLog';
}

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
  List<Map<String, String>> get conversation =>
      List<Map<String, String>>.unmodifiable(_conversation);

  bool _llmInstalled = false;
  bool get llmInstalled => _llmInstalled;
  bool _installingLlm = false;
  bool get installingLlm => _installingLlm;
  String? _llmError;
  String? get llmError => _llmError;

  bool _hideChatLog = false;
  bool get hideChatLog => _hideChatLog;

  Future<void>? _startupFuture;
  bool _startupCompleted = false;

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _hideChatLog = prefs.getBool(AppPreferenceKeys.hideChatLog) ?? false;
    notifyListeners();
  }

  Future<void> setHideChatLog(bool value) async {
    if (value == _hideChatLog) return;

    _hideChatLog = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPreferenceKeys.hideChatLog, value);
  }

  Future<void> startup() async {
    if (_startupCompleted) {
      debugPrint('AppController.startup: Already completed, skipping.');
      return;
    }

    final inFlight = _startupFuture;
    if (inFlight != null) {
      debugPrint('AppController.startup: Awaiting in-flight startup...');
      return inFlight;
    }

    final future = _runStartup();
    _startupFuture = future;
    return future;
  }

  Future<void> _runStartup() async {
    debugPrint('AppController.startup: Starting...');

    try {
      await loadPreferences();
      await llm.initialize();
      await models.loadLocalState();
      await models.refreshInstalled();

      debugPrint(
        'AppController.startup: Installed models: ${models.installedModels.length}',
      );
      debugPrint(
        'AppController.startup: Last used model ID: ${models.lastUsedModelId}',
      );

      await _restoreLastUsedModel();

      _startupCompleted = true;
      debugPrint(
        'AppController.startup: Complete. LLM installed: $llmInstalled',
      );
    } finally {
      _startupFuture = null;
    }
  }

  Future<void> _restoreLastUsedModel() async {
    final lastUsedId = models.lastUsedModelId;
    debugPrint('_restoreLastUsedModel: lastUsedId=$lastUsedId');

    if (lastUsedId == null || lastUsedId.trim().isEmpty) {
      debugPrint('_restoreLastUsedModel: No last used model ID, skipping');
      return;
    }

    final stillInstalled = models.installedModels.any(
      (m) => m.id == lastUsedId,
    );

    debugPrint('_restoreLastUsedModel: stillInstalled=$stillInstalled');

    if (!stillInstalled) {
      debugPrint('_restoreLastUsedModel: Model no longer installed, skipping');
      return;
    }

    debugPrint('_restoreLastUsedModel: Activating model $lastUsedId');
    models.setPendingSelection(lastUsedId);
    await models.commitSelection();
    await activateSelectedModel();
  }

  Future<void> activateSelectedModel() async {
    if (_installingLlm) return;

    _clearLlmState();
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

      await llm.installFromLocalFile(
        selected.localPath,
        preferModelType: selected.config.toGemmaModelType(),
        preferModelFileType: selected.config.fileType,
      );

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

  void _clearLlmState() {
    _llmError = null;
    _llmInstalled = false;
  }

  Future<String> chatOnce(String userText) async {
    final memoryData = await memory.loadMemoryData();
    final systemPrompt = await memory.buildSystemPrompt(memory: memoryData);

    _conversation.add(_createMessage('user', userText));
    notifyListeners();

    final assistant = await llm.generateChat(
      systemText: systemPrompt,
      userText: userText,
    );

    _conversation.add(_createMessage('assistant', assistant));
    notifyListeners();

    debugPrint('LLM assistant response:\n$assistant');

    unawaited(_updateMemory());

    return assistant;
  }

  Map<String, String> _createMessage(String role, String text) {
    return <String, String>{'role': role, 'text': text};
  }

  Future<void> _updateMemory() async {
    final allowed = await memory.isAutoUpdateAllowed();
    if (!allowed) return;

    await memory.updateMemoryFromChat(llm: llm);
  }
}
