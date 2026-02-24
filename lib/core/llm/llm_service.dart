import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:googleapis/dataproc/v1.dart';

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

  Future<List<Tool>> _getTools() async {
    final autoUpdateAllowed = await memoryService.isAutoUpdateAllowed();
    return LlmTools.getAvailableTools(
      googleAuthService: googleAuthService,
      googleCalendarService: googleCalendarService,
      isAutoMemoryUpdateAllowed: autoUpdateAllowed,
    );
  }

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
      debugPrint(
        'Session not created error detected, resetting native state and retrying...',
      );
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

  String _buildToolsSystemInstruction(List<Tool> tools) {
    if (!supportsFunctionCalls || tools.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      'You have access to functions and freely call any available function without asking for permission.',
    );
    buffer.writeln(
      'When you do need to call a function, respond with ONLY the JSON in this format: {"name": <function_name>, "parameters": {<argument>: <value>}}',
    );
    buffer.writeln(
      'You must always ensure that the JSON output is valid and follows the correct format.',
    );
    buffer.writeln(
      'You must call only 1 function at a time. Do not call multiple functions in the same response. Do not respond with multiple JSON objects. If you want to call multiple functions, call them one at a time in separate responses.',
    );
    buffer.writeln(
      'After a function is executed, you will receive its result as a tool response. Based on that result, you can call the same function again, call a different function, or continue the conversation without calling any function by responding to the user with normal text.',
    );
    buffer.writeln('<tool_code>');
    for (final tool in tools) {
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

  String _composeSystemText(String systemText, String toolsInstruction) {
    final base = systemText.trim();
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
        final tools = await _getTools();
        final toolsInstruction = _buildToolsSystemInstruction(tools);
        final composedSystemText = _composeSystemText(
          systemText ?? '',
          toolsInstruction,
        );

        await _ensureLatestSystemOnTop(chat, composedSystemText);

        return _generateAndHandleFunctionCalls(
          chat,
          depth: 0,
          message: Message.text(text: userText, isUser: true),
        );
      });
    });
  }

  Future<String> _generateAndHandleFunctionCalls(
    InferenceChat chat, {
    required int depth,
    required Message message,
  }) async {
    if (depth >= _maxFunctionCallDepth) {
      return 'Maximum function call depth reached.';
    }

    final buffer = StringBuffer();
    FunctionCallResponse? pendingFunctionCall;

    if (depth != 0) {
      chat.close();
      chat.session = await chat.sessionCreator!();
    }

    debugPrint(
      'in _generateAndHandleFunctionCalls Adding query chunk to chat: ${message.text}',
    );

    await chat.addQueryChunk(message);

    debugPrint(
      'in _generateAndHandleFunctionCalls Starting to listen for response chunks...',
    );

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
    final toolResponse = await _handleToolCall(functionCall);

    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );

    return _generateAndHandleFunctionCalls(
      chat,
      depth: depth + 1,
      message: toolMessage,
    )
    .onError(
      (error, stackTrace) {
        debugPrint(
          'Error during function call execution: $error\nStackTrace: $stackTrace',
        );
        return 'All done! How can I assist you today?';
      },
    )
    .timeout(
      const Duration(minutes: 1),
      onTimeout: () {
        return 'All done! How can I assist you today?';
      },
    );
  }

  Future<Map<String, dynamic>> _handleToolCall(
    FunctionCallResponse functionCall,
  ) async {
    switch (functionCall.name) {
      case 'update_assistant_soul':
        await memoryService.updateSoulMemoryFromChat(llm: this);
        return {
          'status': 'success',
          'message':
              'Assistant soul memory updated from recent chat context. It will take effect in future responses.',
        };
      case 'update_assistant_identity':
        await memoryService.updateIdentityMemoryFromChat(llm: this);
        return {
          'status': 'success',
          'message':
              'Assistant identity memory updated from recent chat context. It will take effect in future responses.',
        };
      case 'update_user_memory':
        await memoryService.updateUserMemoryFromChat(llm: this);
        return {
          'status': 'success',
          'message':
              'User memory updated from recent chat context. It will take effect in future responses.',
        };
      default:
        return _functionCallHandler.handle(functionCall);
    }
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
    return _extractMemoryFromPrompt(model, prompt);
  }

  Future<String> extractSoulMemoryFromChat(
    String currentMemoryJson, {
    Set<String> lockedFields = const <String>{},
  }) async {
    final model = await _ensureModel();
    final chat = await _ensureChat(model);
    final history = chat.fullHistory;
    final conversationText = _formatHistoryForMemory(history);
    if (conversationText.isEmpty) {
      return '';
    }

    final prompt = _buildSoulMemoryPrompt(
      conversationText,
      currentMemoryJson,
      lockedFields,
    );
    return _extractMemoryFromPrompt(model, prompt);
  }

  Future<String> extractIdentityMemoryFromChat(
    String currentMemoryJson, {
    Set<String> lockedFields = const <String>{},
  }) async {
    final model = await _ensureModel();
    final chat = await _ensureChat(model);
    final history = chat.fullHistory;
    final conversationText = _formatHistoryForMemory(history);
    if (conversationText.isEmpty) {
      return '';
    }

    final prompt = _buildIdentityMemoryPrompt(
      conversationText,
      currentMemoryJson,
      lockedFields,
    );
    return _extractMemoryFromPrompt(model, prompt);
  }

  Future<String> extractUserMemoryFromChat(
    String currentMemoryJson, {
    Set<String> lockedFields = const <String>{},
  }) async {
    final model = await _ensureModel();
    final chat = await _ensureChat(model);
    final history = chat.fullHistory;
    final conversationText = _formatHistoryForMemory(history);
    if (conversationText.isEmpty) {
      return '';
    }

    final prompt = _buildUserMemoryPrompt(
      conversationText,
      currentMemoryJson,
      lockedFields,
    );
    return _extractMemoryFromPrompt(model, prompt);
  }

  Future<String> _extractMemoryFromPrompt(
    InferenceModel model,
    String prompt,
  ) async {
    final memoryChat = await model.createSession(
      temperature: 0.2,
      randomSeed: randomSeed,
      topK: 1,
      topP: topP,
    );
    try {
      await memoryChat.addQueryChunk(Message.text(text: prompt, isUser: true));
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
  }

  static String _formatHistoryForMemory(List<Message> history) {
    // const maxMessages = 20;

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

    // final recent = filtered.length > maxMessages
    //     ? filtered.sublist(filtered.length - maxMessages)
    //     : filtered;

    final buffer = StringBuffer();
    for (final m in filtered) {
      //recent
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
        '- soul: represent assistant core personality, values, behavior rules, and boundaries.\n'
        '- identity: represents assistant name, tone, style, and presentation.\n'
        '- user: represents user profile, preferences, goals, and interaction style, and context.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"schema_version":3,'
        '"soul":{"mission":string|null,"principles":[string|empty],"boundaries":[string|empty],"response_style":[string|empty]},'
        '"identity":{"assistant_name":string|null,"role":string|null,"voice":[string|empty],"behavior_rules":[string|empty]},'
        '"user":{"name":string|null,"traits":[string|empty],"preferences":[string|empty],"goals":[string|empty],"facts":[string|empty]}}\n'
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

  static String _buildSoulMemoryPrompt(
    String conversation,
    String currentMemory,
    Set<String> lockedFields,
  ) {
    final locked = lockedFields.where((f) => f.startsWith('soul.')).toList()
      ..sort();
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
        'TASK: Update only the soul memory using explicit user intent from the conversation.\n'
        '- Soul memory: represent assistant core personality, values, behavior rules, and boundaries.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"mission":string|null,"principles":[string|empty],"boundaries":[string|empty],"response_style":[string|empty]}\n'
        '\n'
        'RULES:\n'
        '- Keep text concise and stable (max 5 entries per array).\n'
        '- Preserve unchanged existing entries whenever not contradicted.\n'
        '- Replace contradicted entries only with newer explicit user intent.\n'
        '- Do not include identity or user fields.\n'
        '- Fields listed in <locked_fields> are immutable.\n'
        '- Important: You Must NOT infer or guess missing information\n'
        '- Important: Do not make assumptions, random guesses, or fabricated information.\n';
  }

  static String _buildIdentityMemoryPrompt(
    String conversation,
    String currentMemory,
    Set<String> lockedFields,
  ) {
    final locked = lockedFields.where((f) => f.startsWith('identity.')).toList()
      ..sort();
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
        'TASK: Update only the identity memory using explicit user intent from the conversation.\n'
        '- Identity memory: represents assistant name, tone, style, and presentation.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"assistant_name":string|null,"role":string|null,"voice":[string|empty],"behavior_rules":[string|empty]}\n'
        '\n'
        'RULES:\n'
        '- Keep text concise and stable (max 5 entries per array).\n'
        '- Preserve unchanged existing entries whenever not contradicted.\n'
        '- Replace contradicted entries only with newer explicit user intent.\n'
        '- Do not include soul or user fields.\n'
        '- Fields listed in <locked_fields> are immutable.\n'
        '- Important: You Must NOT infer or guess missing information\n'
        '- Important: Do not make assumptions, random guesses, or fabricated information.\n';
  }

  static String _buildUserMemoryPrompt(
    String conversation,
    String currentMemory,
    Set<String> lockedFields,
  ) {
    final locked = lockedFields.where((f) => f.startsWith('user.')).toList()
      ..sort();
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
        'TASK: Update only the user profile memory using explicit user intent from the conversation.\n'
        '- User profile memory: represents user profile, preferences, goals, and interaction style, and context.\n'
        '\n'
        'Output ONLY valid JSON, no explanation, no markdown:\n'
        '{"name":string|null,"traits":[string|empty],"preferences":[string|empty],"goals":[string|empty],"facts":[string|empty]}\n'
        '\n'
        'RULES:\n'
        '- Keep text concise and stable (max 5 entries per array).\n'
        '- Preserve unchanged existing entries whenever not contradicted.\n'
        '- Replace contradicted entries only with newer explicit user intent.\n'
        '- Ignore one-off requests and transient details.\n'
        '- Do not include soul or identity fields.\n'
        '- Important: You Must NOT infer or guess missing information\n'
        '- Important: Do not make assumptions, random guesses, or fabricated information.\n';
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
