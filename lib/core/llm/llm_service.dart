import 'dart:async';
import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/services.dart';
import 'package:mybuddy/core/google/google_auth_service.dart';
import 'package:mybuddy/core/google/google_calendar_service.dart';
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
    this.googleAuthService,
    this.googleCalendarService,
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
  GoogleAuthService? googleAuthService;
  GoogleCalendarService? googleCalendarService;

  static const Tool _animateCharacterTool = Tool(
    name: 'animate_character',
    description:
        "Makes the character perform a specified animation. The animation name should be one of the following: jump, spin, clap, thankful, greet, dance, chicken_dance, think.",
    parameters: {
      'type': 'object',
      'properties': {
        'animation': {
          'type': 'string',
          'description':
              'Animation to perform. Choose one of: jump, spin, clap, thankful, greet, dance, chicken_dance, think.',
        },
        'animate_count': {
          'type': 'int',
          'description':
              'Number of times to perform the animation (only for certain animations). Default is 1.',
        },
        'response_text': {
          'type': 'string',
          'description':
              "Text response that responds to the user's input with empathy and relevance",
        },
        'required': ['animation', 'animate_count', 'response_text'],
      },
    },
  );

  static const Tool _createCalendarEventTool = Tool(
    name: 'create_calendar_event',
    description:
        'Creates a new event on the user\'s Google Calendar. Use this when the user wants to schedule an appointment, reminder, meeting, or any calendar event. Parse natural language dates/times from the user\'s request.',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'description': 'The title or name of the event.',
        },
        'description': {
          'type': 'string',
          'description': 'Optional description or notes for the event.',
        },
        'start_date': {
          'type': 'string',
          'description':
              'The start date and time in ISO 8601 format (e.g., "2026-02-15T14:00:00"). For all-day events, use date only (e.g., "2026-02-15").',
        },
        'end_date': {
          'type': 'string',
          'description':
              'The end date and time in ISO 8601 format. For all-day events, use date only. If not specified, defaults to 1 hour after start.',
        },
        'is_all_day': {
          'type': 'boolean',
          'description': 'Whether this is an all-day event. Default is false.',
        },
        'location': {
          'type': 'string',
          'description': 'Optional location for the event.',
        },
        'response_text': {
          'type': 'string',
          'description':
              'A friendly confirmation message to tell the user about the created event.',
        },
      },
      'required': ['title', 'start_date', 'response_text'],
    },
  );

  List<Tool> get _tools {
    final tools = <Tool>[_animateCharacterTool];

    if (googleAuthService?.isSignedIn == true &&
        googleCalendarService != null) {
      tools.add(_createCalendarEventTool);
    }

    return tools;
  }

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

  Future<void> _animateCharacterJump(int jumpCount) async {
    jumpCount = jumpCount.clamp(1, 10);
    final jumpAnimationIndex = 0;
    for (int i = 0; i < jumpCount; i++) {
      unawaited(unityBridge.playAnimation(jumpAnimationIndex));
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<String> _handleFunctionCall(
    FunctionCallResponse functionCall,
    InferenceChat chat,
  ) async {
    switch (functionCall.name) {
      case 'animate_character':
        final animation = functionCall.args['animation'] as String?;
        final animateCount = functionCall.args['animate_count'] as int?;
        final responseText = functionCall.args['response_text'] as String?;
        switch (animation) {
          case 'jump':
            final jumpCount = animateCount ?? 1;
            unawaited(_animateCharacterJump(jumpCount));
            break;
          case 'spin':
            final spinAnimationIndex = 1;
            unawaited(unityBridge.playAnimation(spinAnimationIndex));
            break;
          case 'clap':
            final clapAnimationIndex = 3;
            unawaited(unityBridge.playAnimation(clapAnimationIndex));
            break;
          case 'thankful':
            final thankfulAnimationIndex = 7;
            unawaited(unityBridge.playAnimation(thankfulAnimationIndex));
            break;
          case 'greet':
            final greetAnimationIndex = 8;
            unawaited(unityBridge.playAnimation(greetAnimationIndex));
            break;
          case 'dance':
            final danceAnimationIndex = Random().nextInt(3) + 9; // 9,10,11
            unawaited(unityBridge.playAnimation(danceAnimationIndex));
            break;
          case 'chicken_dance':
            final chickenDanceAnimationIndex = 4;
            unawaited(unityBridge.playAnimation(chickenDanceAnimationIndex));
            break;
          case 'think':
            final thinkAnimationIndex = 2;
            unawaited(unityBridge.playAnimation(thinkAnimationIndex));
            break;
          default:
            final thankfulAnimationIndex = 7;
            unawaited(unityBridge.playAnimation(thankfulAnimationIndex));
            break;
        }
        return responseText ?? functionCall.toString();

      case 'create_calendar_event':
        return await _handleCreateCalendarEvent(functionCall);

      default:
        return functionCall.toString();
    }
  }

  Future<String> _handleCreateCalendarEvent(
    FunctionCallResponse functionCall,
  ) async {
    final calendarService = googleCalendarService;
    final authService = googleAuthService;

    if (calendarService == null ||
        authService == null ||
        !authService.isSignedIn) {
      return functionCall.args['response_text'] as String? ??
          'Sorry, I couldn\'t create the event. Please sign in to Google Calendar first.';
    }

    try {
      final title = functionCall.args['title'] as String?;
      final description = functionCall.args['description'] as String?;
      final startDateStr = functionCall.args['start_date'] as String?;
      final endDateStr = functionCall.args['end_date'] as String?;
      final isAllDay = functionCall.args['is_all_day'] as bool? ?? false;
      final location = functionCall.args['location'] as String?;
      final responseText = functionCall.args['response_text'] as String?;

      if (title == null || startDateStr == null) {
        return responseText ??
            'Sorry, I need at least a title and date to create an event.';
      }

      final startTime = DateTime.tryParse(startDateStr);
      if (startTime == null) {
        return responseText ?? 'Sorry, I couldn\'t understand the date format.';
      }

      DateTime endTime;
      if (endDateStr != null) {
        endTime =
            DateTime.tryParse(endDateStr) ??
            startTime.add(const Duration(hours: 1));
      } else {
        endTime = isAllDay
            ? startTime.add(const Duration(days: 1))
            : startTime.add(const Duration(hours: 1));
      }

      final result = await calendarService.createEvent(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
      );

      if (result.isSuccess) {
        return responseText ?? 'I\'ve added "$title" to your calendar.';
      } else {
        return responseText ??
            'Sorry, I couldn\'t create the event: ${result.error}';
      }
    } catch (e) {
      return functionCall.args['response_text'] as String? ??
          'Sorry, something went wrong while creating the event.';
    }
  }

  String cleanLLMResponse(String text) {
    String cleaned = text;

    RegExp thinkingRegex = RegExp(r'<think>.*?</think>', dotAll: true);

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

        final s = (systemText ?? '');
        await _ensureLatestSystemOnTop(chat, s);

        await chat.addQueryChunk(Message.text(text: userText, isUser: true));

        final buffer = StringBuffer();
        // Object? lastNonText;

        await for (final r in chat.generateChatResponseAsync()) {
          if (r is TextResponse) {
            buffer.write(r.token);
          } else if (r is FunctionCallResponse) {
            String textResponse = await _handleFunctionCall(r, chat);
            buffer.write(textResponse);
          } else {
            continue;
          }
        }

        String text = buffer.toString();
        // if (lastNonText != null && text.isEmpty) text = lastNonText.toString();
        final cleanedResponse = cleanLLMResponse(text);
        try {
          final cleanedResponsFuncCall = FunctionCallParser.parse(
            cleanedResponse,
            modelType: modelType,
          );
          if (cleanedResponsFuncCall == null) {
            return cleanedResponse;
          }
          String textResponse = await _handleFunctionCall(
            cleanedResponsFuncCall,
            chat,
          );
          return textResponse;
        } catch (e) {
          return cleanedResponse;
        }
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
