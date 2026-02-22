import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../shared/utils/json_extractor.dart';
import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';
import '../unity/unity_bridge.dart';
import 'function_call_handler.dart';
import 'llm_tools.dart';

class LlmService {
  LlmService({
    this.modelType = ModelType.qwen,
    this.preferredBackend = PreferredBackend.gpu,
    this.maxTokens = 4096,
    this.tokenBuffer = 3584,
    this.temperature = 0.8,
    this.randomSeed = 1,
    this.topK = 1,
    this.topP,
    this.isThinking = false,
    this.supportsFunctionCalls = false,
    this.modelFileType = ModelFileType.task,
    required this.unityBridge,
    this.googleAuthService,
    this.googleCalendarService,
  });

  factory LlmService.dummy() => LlmService(unityBridge: UnityBridge());

  ModelType modelType;
  PreferredBackend preferredBackend;
  int maxTokens;
  int tokenBuffer;
  double temperature;
  int randomSeed;
  int topK;
  double? topP;
  bool isThinking;
  bool supportsFunctionCalls;
  ModelFileType modelFileType;

  final UnityBridge unityBridge;
  final GoogleAuthService? googleAuthService;
  final GoogleCalendarService? googleCalendarService;

  InferenceModel? _model;
  InferenceChat? _chat;
  Future<void> _pending = Future<void>.value();
  bool _initialized = false;

  late final FunctionCallHandler _functionCallHandler = FunctionCallHandler(
    unityBridge: unityBridge,
    googleAuthService: googleAuthService,
    googleCalendarService: googleCalendarService,
  );

  List<Tool> get _tools => LlmTools.getAvailableTools(
    googleAuthService: googleAuthService,
    googleCalendarService: googleCalendarService,
  );

  Future<void> initialize({String? huggingFaceToken}) async {
    if (_initialized) return;
    FlutterGemma.initialize(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: 10,
    );
    _initialized = true;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final future = _pending.then((_) => action());
    _pending = future.then((_) {}, onError: (_) {});
    return future;
  }

  bool _isSessionNotCreatedError(Object error) {
    if (error is PlatformException) {
      final msg = (error.message ?? '').toLowerCase();
      final code = error.code.toLowerCase();
      if (code.contains('illegalstateexception') &&
          msg.contains('session not created')) {
        return true;
      }
      if (msg.contains('session not created')) return true;
    }
    return error.toString().toLowerCase().contains('session not created');
  }

  Future<void> _resetNativeState() async {
    final model = _model;
    _chat = null;
    _model = null;
    // _lastSystemText = null;
    if (model != null) {
      try {
        await model.close();
      } catch (_) {}
    }
  }

  Future<void> applyConfig({
    required ModelType modelType,
    required int maxTokens,
    required int tokenBuffer,
    required double temperature,
    required int randomSeed,
    required int topK,
    required double? topP,
    required bool isThinking,
    required bool supportsFunctionCalls,
    required ModelFileType modelFileType,
  }) async {
    this.modelType = modelType;
    this.maxTokens = maxTokens;
    this.tokenBuffer = tokenBuffer;
    this.temperature = temperature;
    this.randomSeed = randomSeed;
    this.topK = topK;
    this.topP = topP;
    this.isThinking = isThinking;
    this.supportsFunctionCalls = supportsFunctionCalls;
    this.modelFileType = modelFileType;

    await _resetNativeState();
  }

  Future<T> _withRecovery<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      if (!_isSessionNotCreatedError(e)) rethrow;
      await _resetNativeState();
      return await action();
    }
  }

  Future<InferenceModel> _ensureModel() async {
    if (_model != null) return _model!;

    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
      );
      _model = model;
      return model;
    } catch (_) {
      await _resetNativeState();
      await Future<void>.delayed(const Duration(seconds: 2));

      final retryModel = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
      );
      _model = retryModel;
      return retryModel;
    }
  }

  Future<InferenceChat> _ensureChat(InferenceModel model) async {
    if (_chat != null) return _chat!;
    final chat = await model.createChat(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      topP: topP,
      tokenBuffer: tokenBuffer,
      supportsFunctionCalls: supportsFunctionCalls,
      isThinking: isThinking,
      modelType: modelType,
      tools: _tools,
    );
    _chat = chat;
    return chat;
  }

  List<Message> _tailConversation(
    List<Message> history, {
    required int maxMessages,
  }) {
    if (history.isEmpty) return const <Message>[];
    final turns = history.where((m) {
      if (m.hasImage) return true;
      if (m.type != MessageType.text) return false;

      if (!m.isUser) {
        final t = m.text.trimLeft();
        if (t.startsWith(
          'This is a system instruction. You must follow it strictly.',
        )) {
          return false;
        }
      }

      return true;
    }).toList();

    // if (turns.length <= maxMessages) return turns;
    // return turns.sublist(turns.length - maxMessages);
    return turns;
  }

  Future<void> _ensureLatestSystemOnTop(
    InferenceChat chat,
    String systemText,
  ) async {
    final s = systemText.trim();
    if (s.isEmpty) return;
    // if (s == _lastSystemText) return;

    final history = chat.fullHistory;
    const maxReplayMessages = 20;
    final replayTail = _tailConversation(
      history,
      maxMessages: maxReplayMessages,
    );

    await chat.clearHistory(
      replayHistory: <Message>[
        ...replayTail,
        Message.text(text: s, isUser: false),
      ],
    );
    // _lastSystemText = s;
  }

  Future<void> installFromLocalFile(
    String localPath, {
    ModelType? preferModelType,
    ModelFileType? preferModelFileType,
  }) async {
    await FlutterGemma.installModel(
      modelType: preferModelType ?? modelType,
      fileType: preferModelFileType ?? modelFileType,
    ).fromFile(localPath).install();
    await _ensureModel();
  }

  /// Generates a single text response from a prompt.
  Future<String> generateText(String prompt) async {
    return _enqueue(() async {
      return _withRecovery(() async {
        final model = await _ensureModel();
        final session = await model.createSession(
          temperature: temperature,
          randomSeed: randomSeed,
          topK: topK,
          topP: topP,
        );
        try {
          await session.addQueryChunk(Message.text(text: prompt, isUser: true));
          final response = await session.getResponse();
          return response;
        } finally {
          await session.close();
        }
      });
    });
  }

  String _cleanResponse(String text) {
    String cleaned = text;

    final thinkingRegex = RegExp(r'<think>.*?</think>', dotAll: true);
    cleaned = cleaned.replaceAll(thinkingRegex, '').trim();

    cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn>\s*$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>\s*$'), '').trim();
    cleaned = cleaned.replaceAll(r'\n', '\n').trim();

    return cleaned;
  }

  Future<String> generateChat({
    String? systemText,
    required String userText,
  }) async {
    return _enqueue(() async {
      return _withRecovery(() async {
        final model = await _ensureModel();
        final chat = await _ensureChat(model);

        await _ensureLatestSystemOnTop(chat, systemText ?? '');
        await chat.addQueryChunk(Message.text(text: userText, isUser: true));

        final buffer = StringBuffer();

        await for (final response in chat.generateChatResponseAsync()) {
          if (response is TextResponse) {
            buffer.write(response.token);
          } else if (response is FunctionCallResponse) {
            final textResponse = await _functionCallHandler.handle(response);
            buffer.write(textResponse);
          }
        }

        final text = buffer.toString();
        final cleanedResponse = _cleanResponse(text);

        return _processJsonFunctionCalls(cleanedResponse);
      });
    });
  }

  Future<String> _processJsonFunctionCalls(String response) async {
    final blocks = extractJsonBlocks(response);
    if (blocks.isEmpty) {
      return response;
    }

    final results = StringBuffer();
    for (final block in blocks) {
      final functionCall = FunctionCallParser.parse(
        block,
        modelType: modelType,
      );
      if (functionCall == null) continue;

      final textResponse = await _functionCallHandler.handle(functionCall);
      results.writeln(textResponse);
    }

    final result = results.toString().trim();
    return result.isNotEmpty ? result : response;
  }

  Future<String> extractMemoryFromChat(String currentMemoryJson) async {
    return _enqueue(() async {
      return _withRecovery(() async {
        final chat = _chat;
        if (chat == null) return '';

        final history = chat.fullHistory;
        if (history.length < 2) return '';

        final conversationText = _formatHistoryForMemory(history);
        if (conversationText.isEmpty) return '';

        final prompt = _buildMemoryPrompt(conversationText, currentMemoryJson);

        final model = await _ensureModel();
        final session = await model.createSession(
          temperature: 0.2,
          randomSeed: randomSeed,
          topK: 1,
        );
        try {
          await session.addQueryChunk(Message.text(text: prompt, isUser: true));
          final response = await session.getResponse();
          return _cleanResponse(response);
        } finally {
          await session.close();
        }
      });
    });
  }

  static String _formatHistoryForMemory(List<Message> history) {
    const maxMessages = 20;
    const maxCharsPerMessage = 200;

    final filtered = history.where((m) {
      if (m.hasImage) return false;
      if (m.type != MessageType.text) return false;
      final text = m.text.trim();
      if (text.isEmpty) return false;
      if (!m.isUser && text.startsWith('This is a system instruction')) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) return '';

    final recent = filtered.length > maxMessages
        ? filtered.sublist(filtered.length - maxMessages)
        : filtered;

    final buffer = StringBuffer();
    for (final m in recent) {
      final role = m.isUser ? 'User' : 'Assistant';
      var text = m.text.trim();
      if (text.length > maxCharsPerMessage) {
        text = '${text.substring(0, maxCharsPerMessage)}…';
      }
      buffer.writeln('$role: $text');
    }
    return buffer.toString().trim();
  }

  static String _buildMemoryPrompt(String conversation, String currentMemory) {
    return '<conversation>\n'
        '$conversation\n'
        '</conversation>\n'
        '\n'
        '<current_memory>\n'
        '$currentMemory\n'
        '</current_memory>\n'
        '\n'
        'TASK: Extract and update stable personal facts about "User" from the <conversation>'
        'Merge them into <current_memory>.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"name":string|null,"traits":[string],"preferences":[string],'
        '"goals":[string],"facts":[string]}\n'
        '\n'
        'RULES:\n'
        '- ≤8 words per entry, max 5 per array\n'
        '- Only long-term, stable personal information\n'
        '- Preserve unchanged existing entries\n'
        '- Replace contradicted entries\n'
        '- Ignore small talk, greetings, ephemeral details\n'
        '- Do NOT infer or guess missing information\n';
  }

  Future<void> close() async {
    final model = _model;
    _chat = null;
    _model = null;
    if (model != null) {
      await model.close();
    }
  }
}
