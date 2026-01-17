import 'dart:async';
import 'dart:math';

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
    // const Tool(
    //   name: 'character_pushup',
    //   description:
    //       "Makes the character do push-ups. The number of push-ups can be specified. Default is 1.",
    //   parameters: {
    //     'type': 'object',
    //     'properties': {
    //       'total': {
    //         'type': 'int',
    //         'description': 'The number of push-ups to perform',
    //       },
    //     },
    //     'required': ['total'],
    //   },
    // ),
    const Tool(
      name: 'animate_character',
      description:
          "Makes the character perform a specified animation. The animation name should be one of the following: [spin,clap,thankful,greet,dance,chicken_dance, think]",
      parameters: {
        'type': 'object',
        'properties': {
          'animation': {
            'type': 'string',
            'description':
                'Animation to perform. Choose one of: spin, clap, thankful, greet, dance, chicken_dance, think.',
          },
        },
        'required': ['animation'],
      },
    ),
    // const Tool(
    //   name: 'character_spin/turn_around',
    //   description: "Makes the character spin or turn around.",
    // ),
    // const Tool(
    //   name: 'character_clap',
    //   description:
    //       "Makes the character clap their hands applauding. especially congratulations for users or after receiving praise",
    // ),
    // const Tool(
    //   name: 'character_thankful',
    //   description:
    //       "Makes the character perform a thankful gesture. especially after receiving help from the user.",
    // ),
    // const Tool(
    //   name: 'character_greet',
    //   description:
    //       "Makes the character perform a greeting gesture. especially for greeting the users.",
    // ),
    // const Tool(
    //   name: 'character_dance',
    //   description: "Makes the character perform a dance routine.",
    // ),
    // const Tool(
    //   name: 'character_chicken_dance',
    //   description:
    //       "Makes the character perform the chicken dance. (special dance only perform when user request)",
    // ),
  ];

  InferenceModel? _model;
  InferenceChat? _chat;
  // String? _lastSystemText;

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
    const maxReplayMessages = 20;
    final replayTail = _tailConversation(
      history,
      maxMessages: maxReplayMessages,
    );

    await chat.clearHistory(
      replayHistory: <Message>[
        Message.text(text: s, isUser: false),
        ...replayTail,
      ],
    );
    // _lastSystemText = s;
  }

  Future<void> installFromLocalFile(String localPath) async {
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: modelFileType,
    ).fromFile(localPath).install();
    await _ensureModel();
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
    switch (functionCall.name) {
      case 'character_jump':
        final total = functionCall.args['total'] as int?;
        final jumpCount = (total != null && total > 0 ? total : 1).clamp(1, 10);
        final jumpAnimationIndex = 0;
        for (int i = 0; i < jumpCount; i++) {
          await unityBridge.playAnimation(jumpAnimationIndex);
          await Future.delayed(const Duration(seconds: 3));
        }
        break;
      case 'character_pushup':
        final total = functionCall.args['total'] as int?;
        final pushupCount = (total != null && total > 0 ? total : 1).clamp(
          1,
          10,
        );
        final startplankAnimationIndex = 5;
        final pushupAnimationIndex = 6;
        await unityBridge.playAnimation(startplankAnimationIndex);
        await Future.delayed(const Duration(seconds: 4));
        for (int i = 0; i < pushupCount; i++) {
          await unityBridge.playAnimation(pushupAnimationIndex);
          await Future.delayed(const Duration(milliseconds: 700));
        }
        break;
      case 'animate_character':
        final animation = functionCall.args['animation'] as String?;
        switch (animation) {
          case 'spin':
            final spinAnimationIndex = 1;
            await unityBridge.playAnimation(spinAnimationIndex);
            break;
          case 'clap':
            final clapAnimationIndex = 3;
            await unityBridge.playAnimation(clapAnimationIndex);
            break;
          case 'thankful':
            final thankfulAnimationIndex = 7;
            await unityBridge.playAnimation(thankfulAnimationIndex);
            break;
          case 'greet':
            final greetAnimationIndex = 8;
            await unityBridge.playAnimation(greetAnimationIndex);
            break;
          case 'dance':
            final danceAnimationIndex = Random().nextInt(3) + 9; // 9,10,11
            await unityBridge.playAnimation(danceAnimationIndex);
            break;
          case 'chicken_dance':
            final chickenDanceAnimationIndex = 4;
            await unityBridge.playAnimation(chickenDanceAnimationIndex);
            break;
          case 'think':
            final thinkAnimationIndex = 2;
            await unityBridge.playAnimation(thinkAnimationIndex);
            break;
          default:
            final thankfulAnimationIndex = 7;
            await unityBridge.playAnimation(thankfulAnimationIndex);
            break;
        }
      // case 'character_spin/turn_around':
      //   final spinAnimationIndex = 1;
      //   unawaited(unityBridge.playAnimation(spinAnimationIndex));
      //   break;
      // case 'character_clap':
      //   final clapAnimationIndex = 3;
      //   unawaited(unityBridge.playAnimation(clapAnimationIndex));
      //   break;
      // case 'character_thankful':
      //   final thankfulAnimationIndex = 7;
      //   unawaited(unityBridge.playAnimation(thankfulAnimationIndex));
      //   break;
      // case 'character_greet':
      //   final greetAnimationIndex = 8;
      //   unawaited(unityBridge.playAnimation(greetAnimationIndex));
      //   break;
      // case 'character_dance':
      //   final danceAnimationIndex = Random().nextInt(3) + 9; // 9,10,11
      //   unawaited(unityBridge.playAnimation(danceAnimationIndex));
      //   break;
      // case 'character_chicken_dance':
      //   final chickenDanceAnimationIndex = 4;
      //   unawaited(unityBridge.playAnimation(chickenDanceAnimationIndex));
      //   break;
    }
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
    // _lastSystemText = null;
    if (model != null) {
      await model.close();
    }
  }
}
