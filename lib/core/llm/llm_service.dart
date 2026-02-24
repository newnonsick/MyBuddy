import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../shared/utils/json_extractor.dart';
import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';
import '../memory/memory_service.dart';
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
    required this.memoryService,
    this.googleAuthService,
    this.googleCalendarService,
  });

  factory LlmService.dummy() =>
      LlmService(unityBridge: UnityBridge(), memoryService: MemoryService());

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
  final MemoryService memoryService;
  final GoogleAuthService? googleAuthService;
  final GoogleCalendarService? googleCalendarService;

  InferenceModel? _model;
  InferenceChat? _chat;
  Future<void> _pending = Future<void>.value();
  bool _initialized = false;
  static final Object _enqueueZoneKey = Object();

  late final FunctionCallHandler _functionCallHandler = FunctionCallHandler(
    unityBridge: unityBridge,
    memoryService: memoryService,
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

  Future<T> _enqueue<T>(
    Future<T> Function() action, {
    bool forceQueued = false,
  }) {
    final isNested = !forceQueued && Zone.current[_enqueueZoneKey] == true;
    if (isNested) {
      return action();
    }

    final future = _pending
        .then(
          (_) => runZoned<Future<T>>(
            action,
            zoneValues: <Object?, Object?>{_enqueueZoneKey: true},
          ),
        )
        .then((value) => value);
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
      tools: const <Tool>[],
    );
    _chat = chat;
    return chat;
  }

  String _buildToolsSystemInstruction() {
    if (!supportsFunctionCalls || _tools.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      'You have access to functions and freely call any available function without asking for permission.',
    );
    buffer.writeln(
      'When you do need to call a function, respond with ONLY the JSON in this format: {"name": <function_name>, "parameters": {<argument>: <value>}}',
    );
    buffer.writeln(
      'Example: {"name": "animate_character", "parameters": {"animation": "jump", "animate_count": 2}}',
    );
    buffer.writeln(
      'You must always ensure that the JSON output is valid and follows the correct format.',
    );
    buffer.writeln(
      'After a function is executed, you will receive its result as a tool response. Based on that result, you may call the same function again, call a different function, or provide a helpful natural language message to the user about what was accomplished. Do NOT include the function response verbatim — summarize the outcome naturally.',
    );
    buffer.writeln('<tool_code>');
    for (final tool in _tools) {
      buffer.writeln(
        jsonEncode(<String, Object?>{
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
        }),
      );
    }
    buffer.writeln('</tool_code>');
    return buffer.toString().trim();
  }

  String _composeSystemText(String systemText) {
    final base = systemText.trim();
    final toolsInstruction = _buildToolsSystemInstruction();
    if (toolsInstruction.isEmpty) return base;
    if (base.isEmpty) return toolsInstruction;
    return '$base\n\n$toolsInstruction';
  }

  List<Message> _tailConversation(
    List<Message> history, {
    required int maxMessages,
  }) {
    if (history.isEmpty) return const <Message>[];
    final turns = history.where((m) {
      if (m.hasImage) return true;
      if (m.type != MessageType.text) {
        // && m.type != MessageType.toolResponse
        return false;
      }

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

    if (turns.length <= maxMessages) return turns;
    return turns.sublist(turns.length - maxMessages);
  }

  Future<void> _ensureLatestSystemOnTop(
    InferenceChat chat,
    String systemText,
  ) async {
    final s = systemText.trim();
    if (s.isEmpty) return;
    // if (s == _lastSystemText) return;

    final history = chat.fullHistory;
    const maxReplayMessages = 26;
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

  static const int _maxFunctionCallDepth = 10;

  Future<String> generateChat({
    String? systemText,
    required String userText,
  }) async {
    return _enqueue(() async {
      return _withRecovery(() async {
        final model = await _ensureModel();
        final chat = await _ensureChat(model);
        final composedSystemText = _composeSystemText(systemText ?? '');

        await _ensureLatestSystemOnTop(chat, composedSystemText);
        await chat.addQueryChunk(Message.text(text: userText, isUser: true));

        return _generateAndHandleFunctionCalls(chat, depth: 0);
      });
    });
  }

  Future<String> _generateAndHandleFunctionCalls(
    InferenceChat chat, {
    required int depth,
  }) async {
    if (depth >= _maxFunctionCallDepth) {
      return 'Maximum function call depth reached.';
    }

    final buffer = StringBuffer();
    FunctionCallResponse? pendingFunctionCall;

    await for (final response in chat.generateChatResponseAsync()) {
      debugPrint(
        'Received response chunk: $response type: ${response.runtimeType}',
      );
      if (response is TextResponse) {
        buffer.write(response.token);
      } else if (response is FunctionCallResponse) {
        pendingFunctionCall = response;
      }
    }

    if (pendingFunctionCall != null) {
      return _executeFunctionCallAndContinue(
        chat,
        pendingFunctionCall,
        depth: depth,
      );
    }

    final text = buffer.toString();
    final cleanedResponse = _cleanResponse(text);

    return _processJsonFunctionCalls(chat, cleanedResponse, depth: depth);
  }

  Future<String> _executeFunctionCallAndContinue(
    InferenceChat chat,
    FunctionCallResponse functionCall, {
    required int depth,
  }) async {
    final toolResponse = await _functionCallHandler.handle(functionCall);

    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );
    await chat.addQueryChunk(toolMessage);

    return _generateAndHandleFunctionCalls(chat, depth: depth + 1);
  }

  Future<String> _processJsonFunctionCalls(
    InferenceChat chat,
    String response, {
    required int depth,
  }) async {
    final blocks = extractJsonBlocks(response);
    if (blocks.isEmpty) {
      return response;
    }

    for (final block in blocks) {
      final functionCall = FunctionCallParser.parse(
        block,
        modelType: modelType,
      );
      if (functionCall == null) continue;

      return _executeFunctionCallAndContinue(chat, functionCall, depth: depth);
    }

    return response;
  }

  Future<String> extractMemoryFromChat(
    String currentMemoryJson, {
    Set<String> lockedFields = const <String>{},
  }) async {
    return _enqueue(() async {
      return _withRecovery(() async {
        final model = await _ensureModel();
        final chat = await _ensureChat(model);
        final history = chat.fullHistory;
        final conversationText = _formatHistoryForMemory(history);
        if (conversationText.isEmpty) {
          return '';
        }

        final prompt = _buildMemoryPrompt(
          conversationText,
          currentMemoryJson,
          lockedFields,
        );
        final memoryChat = await model.createSession(
          temperature: 0.2,
          randomSeed: randomSeed,
          topK: 1,
          topP: topP,
        );
        try {
          await memoryChat.addQueryChunk(
            Message.text(text: prompt, isUser: true),
          );
          final responseBuffer = StringBuffer();
          await for (final chunk in memoryChat.getResponseAsync()) {
            debugPrint('Memory extraction chunk: $chunk');
            responseBuffer.write(chunk);
          }
          final fullResponse = responseBuffer.toString();
          return _cleanResponse(fullResponse);
        } finally {
          await memoryChat.close();
        }
      });
    });
  }

  static String _formatHistoryForMemory(List<Message> history) {
    const maxMessages = 20;

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
      final text = m.text.trim();
      buffer.writeln('$role: $text');
    }
    return buffer.toString().trim();
  }

  static String _buildMemoryPrompt(
    String conversation,
    String currentMemory,
    Set<String> lockedFields,
  ) {
    final locked = lockedFields.toList()..sort();
    final lockedText = locked.isEmpty ? '(none)' : locked.join(', ');

    return '<conversation>\n'
        '$conversation\n'
        '</conversation>\n'
        '\n'
        '<current_memory>\n'
        '$currentMemory\n'
        '</current_memory>\n'
        '\n'
        '<locked_fields>\n'
        '$lockedText\n'
        '</locked_fields>\n'
        '\n'
        'TASK: Update three memory layers from the <conversation> and merge into <current_memory>.\n'
        '- soul: stable assistant operating values explicitly requested by user.\n'
        '- identity: assistant persona details explicitly requested by user.\n'
        '- user: stable, long-term user facts/preferences/goals.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"schema_version":3,'
        '"soul":{"mission":string|null,"principles":[string],"boundaries":[string],"response_style":[string]},'
        '"identity":{"assistant_name":string|null,"role":string|null,"voice":[string],"behavior_rules":[string]},'
        '"user":{"name":string|null,"traits":[string],"preferences":[string],"goals":[string],"facts":[string]}}\n'
        '\n'
        'RULES:\n'
        '- Keep text concise and stable (max 5 entries per array).\n'
        '- Preserve unchanged existing entries whenever not contradicted.\n'
        '- Replace contradicted entries with newer explicit user intent.\n'
        '- Ignore one-off requests, greetings, and transient details.\n'
        '- Do not mutate soul/identity unless user explicitly asks to change assistant behavior/persona.\n'
        '- Fields listed in <locked_fields> are immutable: copy them exactly from <current_memory>.\n'
        '- Important: You Must NOT infer or guess missing information\n'
        '- Important: Do not make assumptions, random guesses, or fabricated information. Any predictions or inferences about the user\'s actions or behavior should be strictly based on the information given by the user.\n';
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
