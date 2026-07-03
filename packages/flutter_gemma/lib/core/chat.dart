import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/function_call_parser.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';

import 'model.dart';

// Constants
/// Maximum length for function call buffer before flushing as text.
/// Must accommodate verbose formats (DeepSeek tags, parallel calls).
const int _maxFunctionBufferLength = 1024;

class InferenceChat {
  final Future<InferenceModelSession> Function()? sessionCreator;
  final int maxTokens;
  final int tokenBuffer;
  final bool supportImage;
  final bool supportAudio;
  final bool supportsFunctionCalls;
  final ModelType modelType; // Add modelType parameter
  final bool isThinking; // Add isThinking flag for thinking models
  final ModelFileType fileType; // Add fileType parameter
  final ToolChoice toolChoice; // Tool calling mode
  late InferenceModelSession session;
  final List<Tool> tools;

  final List<Message> _fullHistory = [];
  final List<Message> _modelHistory = [];
  int _currentTokens = 0;
  bool _toolsInstructionSent =
      false; // Flag to track if tools instruction was sent

  /// Determines if model history should be cleared after each turn
  /// FunctionGemma requires single-turn mode (no multi-turn context)
  bool get _isSingleTurnModel => modelType == ModelType.functionGemma;

  InferenceChat({
    required this.sessionCreator,
    required this.maxTokens,
    this.tokenBuffer = 2000,
    this.supportImage = false,
    this.supportAudio = false,
    this.supportsFunctionCalls = false,
    this.tools = const [],
    this.modelType =
        ModelType.gemmaIt, // Default to gemmaIt for backward compatibility
    this.isThinking = false, // Default to false for backward compatibility
    this.fileType =
        ModelFileType.task, // Default to task for backward compatibility
    this.toolChoice =
        ToolChoice.auto, // Default to auto for backward compatibility
    String?
        systemInstruction, // kept for API compatibility, forwarded to session via sessionCreator
  });

  List<Message> get fullHistory => List.unmodifiable(_fullHistory);

  Future<void> initSession() async {
    session = await sessionCreator!();
  }

  Future<void> addQuery(Message message) async {
    await addQueryChunk(message);
  }

  Future<void> addQueryChunk(Message message, [bool noTool = false]) async {
    var messageToSend = message;

    // Only add tools prompt for the first user text message (not a tool response)
    // and only if the model supports function calls
    if (message.isUser &&
        message.type == MessageType.text &&
        !_toolsInstructionSent &&
        tools.isNotEmpty &&
        !noTool &&
        supportsFunctionCalls &&
        toolChoice != ToolChoice.none) {
      _toolsInstructionSent = true;
      // final toolsPrompt = createToolsPrompt();

      // For FunctionGemma, manually construct the full prompt with turn markers
      // because tools prompt already has developer turn markers
      if (modelType == ModelType.functionGemma) {
        final newText =
            '$startTurn$userPrefix\n${messageToSend.text}\n$endTurn\n$startTurn$modelPrefix\n';
        messageToSend = messageToSend.copyWith(text: newText);
      } else {
        final newText = messageToSend.text;
        messageToSend = messageToSend.copyWith(text: newText);
      }
    } else if (!supportsFunctionCalls && tools.isNotEmpty && !noTool) {
      // Log warning if model doesn't support function calls but tools are provided
      debugPrint(
          'WARNING: Model does not support function calls, but tools were provided. Tools will be ignored.');
    }

    await session.addQueryChunk(messageToSend);

    // Store original message in _modelHistory (not messageToSend) so that
    // _recreateSessionWithReducedChunks replay does not double-apply transformations
    // (e.g. systemInstruction prepend, tools prompt) when the session is recreated.
    _fullHistory.add(messageToSend);
    _modelHistory.add(message);
  }

  Future<ModelResponse> generateChatResponse() async {
    debugPrint('InferenceChat: Getting response from native model...');
    final response = await session.getResponse();
    final cleanedResponse = ModelThinkingFilter.cleanResponse(response,
        isThinking: isThinking, modelType: modelType, fileType: fileType);

    if (cleanedResponse.isEmpty) {
      debugPrint(
          'InferenceChat: Raw response from native model is EMPTY after cleaning.');
      return const TextResponse(''); // Return TextResponse instead of String
    }

    // Try to parse as function call if tools are available and model supports function calls
    if (tools.isNotEmpty &&
        supportsFunctionCalls &&
        toolChoice != ToolChoice.none) {
      final allCalls = FunctionCallParser.parseAll(
        cleanedResponse,
        modelType: modelType,
      );
      if (allCalls.isNotEmpty) {
        debugPrint(
            'InferenceChat: Detected ${allCalls.length} function call(s) in sync response');
        final toolCallMessage = Message.toolCall(text: cleanedResponse);
        _fullHistory.add(toolCallMessage);
        _modelHistory.add(toolCallMessage);
        if (allCalls.length == 1) {
          return allCalls.first;
        }
        return ParallelFunctionCallResponse(calls: allCalls);
      }
    }

    // Regular text response
    final chatMessage = Message(text: cleanedResponse, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    // Clear model history for single-turn models (e.g., FunctionGemma)
    if (_isSingleTurnModel) {
      debugPrint(
          'InferenceChat: Single-turn model detected, clearing model history...');
      _modelHistory.clear();
      _currentTokens = 0;
      _toolsInstructionSent = false;

      // Recreate session to clear native state
      await session.close();
      session = await sessionCreator!();
      debugPrint('InferenceChat: Model history cleared and session recreated');
    }

    return TextResponse(
        cleanedResponse); // Return TextResponse instead of String
  }

  Stream<ModelResponse> generateChatResponseAsync() async* {
    debugPrint('InferenceChat: Starting async stream generation');
    final buffer = StringBuffer();

    // Smart function handling mode - continuous scanning for JSON patterns
    String funcBuffer = '';

    debugPrint('InferenceChat: Starting to iterate over native tokens...');

    // Track if we emitted a function call (to record correct history and skip session clearing)
    bool emittedFunctionCall = false;
    final toolCallHistory = StringBuffer();

    final originalStream =
        session.getResponseAsync().map((token) => TextResponse(token));

    // Apply thinking filter if needed using ModelThinkingFilter
    final Stream<ModelResponse> filteredStream = isThinking
        ? ModelThinkingFilter.filterThinkingStream(originalStream,
            modelType: modelType)
        : originalStream;

    // Apply stop token filter for .litertlm on iOS (MediaPipe doesn't handle stop tokens)
    final Stream<ModelResponse> stopFilteredStream =
        StopTokenFilter.filterStopTokens(filteredStream, fileType: fileType);

    await for (final response in stopFilteredStream) {
      if (response is TextResponse) {
        final token = response.token;
        // Track if this token should be added to buffer (default true)
        bool shouldAddToBuffer = true;

        // Continuous scanning for function calls in text - for models like DeepSeek
        if (tools.isNotEmpty &&
            supportsFunctionCalls &&
            toolChoice != ToolChoice.none) {
          // Check if we're currently buffering potential JSON
          if (funcBuffer.isNotEmpty) {
            // We're already buffering - add token and check for completion
            funcBuffer += token;
            // Check if we now have a complete JSON
            if (FunctionCallParser.isFunctionCallComplete(funcBuffer,
                modelType: modelType)) {
              // First try to extract message from any JSON with message field
              try {
                final jsonData = jsonDecode(funcBuffer);
                if (jsonData is Map<String, dynamic> &&
                    jsonData.containsKey('message')) {
                  // Found JSON with message field - extract and display the message
                  final message = jsonData['message'] as String;
                  yield TextResponse(message);
                  funcBuffer = '';
                  shouldAddToBuffer = false; // Don't add JSON tokens to buffer
                  continue;
                }
              } catch (_) {}

              // If no message field found, try parsing as function call(s)
              final allCalls = FunctionCallParser.parseAll(
                funcBuffer,
                modelType: modelType,
              );
              if (allCalls.isNotEmpty) {
                debugPrint(
                    'InferenceChat: Found ${allCalls.length} function call(s) in complete buffer!');
                emittedFunctionCall = true;
                if (toolCallHistory.isNotEmpty) toolCallHistory.writeln();
                toolCallHistory.write(funcBuffer);
                if (allCalls.length == 1) {
                  yield allCalls.first;
                } else {
                  yield ParallelFunctionCallResponse(calls: allCalls);
                }
                funcBuffer = '';
                shouldAddToBuffer = false;
                continue;
              } else {
                // Not a valid function call - emit as text and clear buffer
                debugPrint('InferenceChat: Invalid JSON, emitting as text');
                yield TextResponse(funcBuffer);
                funcBuffer = '';
                shouldAddToBuffer = false;
                continue;
              }
            }

            // If buffer gets too long without completing, flush as text
            if (funcBuffer.length > _maxFunctionBufferLength) {
              debugPrint(
                  'InferenceChat: Buffer too long without completion, flushing as text');
              yield TextResponse(funcBuffer);
              funcBuffer = '';
              shouldAddToBuffer = false;
              continue;
            }

            // Still buffering, don't emit yet
            shouldAddToBuffer = false;
          } else {
            // Not currently buffering - check if this token starts a function call
            if (FunctionCallParser.isFunctionCallStart(token,
                modelType: modelType)) {
              funcBuffer = token;
              shouldAddToBuffer =
                  false; // Don't add to main buffer while we determine if it's JSON
            } else {
              // Normal text token - emit immediately
              yield response;
              shouldAddToBuffer = true; // Add to main buffer for history
            }
          }
        } else {
          // No function processing happening - emit token directly
          yield response;
          shouldAddToBuffer = true; // Add to main buffer for history
        }

        // Add token to buffer only if it should be included in final message
        if (shouldAddToBuffer) {
          buffer.write(token);
        }
      } else {
        // For non-TextResponse (like ThinkingResponse), pass through
        yield response;
      }
    }

    debugPrint('InferenceChat: Native token stream ended');
    final response = buffer.toString();
    // Handle end of stream - process any remaining buffer
    if (funcBuffer.isNotEmpty) {
      debugPrint(
          'InferenceChat: Processing remaining buffer at end of stream: ${funcBuffer.length} chars');

      // For FunctionGemma, the function call spans response + funcBuffer
      // (e.g., response="<start_function_call>call:fn", funcBuffer="{params}")
      // For JSON models, funcBuffer contains the complete JSON
      final contentToCheck = modelType == ModelType.functionGemma
          ? response + funcBuffer
          : funcBuffer;

      // First try to extract message from JSON if it has message field
      if (FunctionCallParser.isFunctionCallComplete(contentToCheck,
          modelType: modelType)) {
        try {
          // For JSON parsing, use funcBuffer (the actual JSON part)
          // For FunctionGemma parsing, use contentToCheck (full function call)
          if (modelType != ModelType.functionGemma &&
              funcBuffer.trim().startsWith('{')) {
            final jsonData = jsonDecode(funcBuffer);
            if (jsonData is Map<String, dynamic> &&
                jsonData.containsKey('message')) {
              final message = jsonData['message'] as String;
              yield TextResponse(message);
              return;
            }
          }

          // Try to parse as function call(s)
          final allCalls = FunctionCallParser.parseAll(
            contentToCheck,
            modelType: modelType,
          );
          if (allCalls.isNotEmpty) {
            debugPrint(
                'InferenceChat: ${allCalls.length} function call(s) found at end of stream');
            emittedFunctionCall = true;
            if (toolCallHistory.isNotEmpty) toolCallHistory.writeln();
            toolCallHistory.write(contentToCheck);
            if (allCalls.length == 1) {
              yield allCalls.first;
            } else {
              yield ParallelFunctionCallResponse(calls: allCalls);
            }
          } else {
            yield TextResponse(funcBuffer);
          }
        } catch (_) {
          yield TextResponse(funcBuffer);
        }
      } else {
        debugPrint(
            'InferenceChat: No complete JSON at end of stream, emitting remaining as text');
        yield TextResponse(funcBuffer);
      }
    }

    try {
      debugPrint('InferenceChat: Calculating response tokens...');
      final responseTokens = await session.sizeInTokens(response);
      debugPrint('InferenceChat: Response tokens: $responseTokens');
      _currentTokens += responseTokens;
      debugPrint('InferenceChat: Current total tokens: $_currentTokens');

      if (_currentTokens >= (maxTokens - tokenBuffer)) {
        debugPrint('InferenceChat: Token limit reached, recreating session...');
        await _recreateSessionWithReducedChunks();
        debugPrint('InferenceChat: Session recreated successfully');
      }
    } catch (e) {
      debugPrint('InferenceChat: Error during token calculation: $e');
    }

    try {
      debugPrint('InferenceChat: Adding message to history...');
      // Use toolCall message for function calls, text message otherwise
      final chatMessage = emittedFunctionCall
          ? Message.toolCall(text: toolCallHistory.toString())
          : Message(text: response, isUser: false);
      _fullHistory.add(chatMessage);
      debugPrint('InferenceChat: Added to full history');
      _modelHistory.add(chatMessage);
      debugPrint('InferenceChat: Added to model history');
      debugPrint('InferenceChat: Message added to history successfully');

      // Clear model history for single-turn models (e.g., FunctionGemma)
      // BUT only if this was NOT a function call - we need context for tool response
      if (_isSingleTurnModel && !emittedFunctionCall) {
        debugPrint(
            'InferenceChat: Single-turn model detected (text response), clearing model history...');
        _modelHistory.clear();
        _currentTokens = 0;
        _toolsInstructionSent = false;

        // Recreate session to clear native state
        await session.close();
        session = await sessionCreator!();
        debugPrint(
            'InferenceChat: Model history cleared and session recreated');
      } else if (_isSingleTurnModel && emittedFunctionCall) {
        debugPrint(
            'InferenceChat: Single-turn model with function call - keeping history for tool response');
      }
    } catch (e) {
      debugPrint('InferenceChat: Error adding message to history: $e');
      rethrow;
    }

    debugPrint(
        'InferenceChat: generateChatResponseAsync completed successfully');
  }

  Future<void> _recreateSessionWithReducedChunks() async {
    while (_currentTokens >= (maxTokens - tokenBuffer) &&
        _modelHistory.isNotEmpty) {
      final removedMessage = _modelHistory.removeAt(0);
      final size = await session.sizeInTokens(removedMessage.text);
      _currentTokens -= size;

      if (removedMessage.hasImage) {
        _currentTokens -= 257;
      }
    }

    await session.close();
    session = await sessionCreator!();

    for (final message in _modelHistory) {
      await session.addQueryChunk(message);
    }
  }

  Future<void> clearHistory({List<Message>? replayHistory}) async {
    _fullHistory.clear();
    _modelHistory.clear();
    _currentTokens = 0;
    _toolsInstructionSent = false;
    await session.close();
    session = await sessionCreator!();

    if (replayHistory != null) {
      for (final message in replayHistory) {
        await addQueryChunk(message, true);
      }
    }
  }

  bool get supportsImages => supportImage;

  int get imageMessageCount => _fullHistory.where((msg) => msg.hasImage).length;

  Future<void> stopGeneration() => session.stopGeneration();

  Future<void> close() => session.close();
}

/// Filters stop tokens from model response stream.
/// For .litertlm on iOS, MediaPipe doesn't handle `<end_of_turn>` —
/// this filter detects and terminates the stream at the stop token,
/// with buffering for partial tag matches.
class StopTokenFilter {
  static const String _stopToken = '<end_of_turn>';

  static Stream<ModelResponse> filterStopTokens(
    Stream<ModelResponse> originalStream, {
    required ModelFileType fileType,
  }) async* {
    // Only apply for litertlm on iOS
    if (fileType != ModelFileType.litertlm ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      yield* originalStream;
      return;
    }

    String buffer = '';

    await for (final response in originalStream) {
      if (response is TextResponse) {
        buffer += response.token;

        // Check if buffer contains the stop token
        final stopIndex = buffer.indexOf(_stopToken);
        if (stopIndex >= 0) {
          // Emit text before stop token, then stop
          final textBefore = buffer.substring(0, stopIndex);
          if (textBefore.isNotEmpty) {
            yield TextResponse(textBefore);
          }
          return;
        }

        // Check if buffer ends with a partial match of the stop token
        int partialLen = 0;
        for (int i = 1; i <= _stopToken.length && i <= buffer.length; i++) {
          if (buffer.endsWith(_stopToken.substring(0, i))) {
            partialLen = i;
          }
        }

        if (partialLen > 0) {
          // Emit safe portion, keep potential partial match
          final safe = buffer.substring(0, buffer.length - partialLen);
          if (safe.isNotEmpty) {
            yield TextResponse(safe);
          }
          buffer = buffer.substring(buffer.length - partialLen);
        } else {
          // No partial match, emit everything
          if (buffer.isNotEmpty) {
            yield TextResponse(buffer);
          }
          buffer = '';
        }
      } else {
        yield response;
      }
    }

    // Emit any remaining buffer (wasn't a complete stop token)
    if (buffer.isNotEmpty) {
      yield TextResponse(buffer);
    }
  }
}
