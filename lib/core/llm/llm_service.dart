import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/services.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';

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
  });

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
  UnityBridge unityBridge;

  final List<Tool> _tools = [
    const Tool(
      name: 'character_jump',
      description:
          "Makes the character jump. The number of the jump can be specified. Default is 1.",
      parameters: {
        'type': 'object',
        'properties': {
          'total': {
            'type': 'int',
            'description': 'The number of jumps to perform',
          },
        },
        'required': ['total'],
      },
    ),
  ];

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _lastSystemText;

  Future<void> _pending = Future<void>.value();

  bool _initialized = false;

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
    _lastSystemText = null;
    if (model != null) {
      try {
        await model.close();
      } catch (_) {
      }
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
    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
    );
    _model = model;
    return model;
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
        if (t.startsWith('You are a helpful and friendly AI companion.') &&
            t.contains('[Current Memory]:')) {
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
    if (s == _lastSystemText) return;

    final history = chat.fullHistory;
    const maxReplayMessages = 16;
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
    _lastSystemText = s;
  }

  Future<void> installFromLocalFile(String localPath) async {
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: modelFileType,
    ).fromFile(localPath).install();
  }

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

  Future<void> _handleFunctionCall(
    FunctionCallResponse functionCall,
    InferenceChat chat,
  ) async {
    Map<String, dynamic> toolResponse;

    switch (functionCall.name) {
      case 'character_jump':
        final total = functionCall.args['total'] as int?;
        final jumpCount = (total != null && total > 0 ? total : 1).clamp(1, 10);
        for (int i = 0; i < jumpCount; i++) {
          await unityBridge.playAnimation(1);
          await Future.delayed(const Duration(seconds: 3));
        }
        toolResponse = {
          'status': 'success',
          'message': 'Character jumped $jumpCount time(s).',
        };

      default:
        toolResponse = {'error': 'Unknown function: ${functionCall.name}'};
    }

    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );
    await chat.addQueryChunk(toolMessage);
  }

  String cleanLLMResponse(String text) {
    String cleaned = text;

    RegExp thinkingRegex = RegExp(r'<think>.*?</think>', dotAll: true);

    cleaned = cleaned.replaceAll(thinkingRegex, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn>\s*$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>\s*$'), '').trim();

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

        final s = (systemText ?? '');
        await _ensureLatestSystemOnTop(chat, s);

        await chat.addQueryChunk(Message.text(text: userText, isUser: true));

        final buffer = StringBuffer();
        // Object? lastNonText;

        await for (final r in chat.generateChatResponseAsync()) {
          if (r is TextResponse) {
            buffer.write(r.token);
          } else if (r is FunctionCallResponse) {
            await _handleFunctionCall(r, chat);
          } else {
            continue;
          }
        }

        String text = buffer.toString();
        // if (lastNonText != null && text.isEmpty) text = lastNonText.toString();
        final cleanedResponse = cleanLLMResponse(text);
        return cleanedResponse;
      });
    });
  }

  Future<void> close() async {
    final model = _model;
    _chat = null;
    _model = null;
    _lastSystemText = null;
    if (model != null) {
      await model.close();
    }
  }
}
