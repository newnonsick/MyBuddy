import 'package:flutter_gemma/flutter_gemma.dart';

import 'tool_protocol.dart';

abstract interface class ToolLoopChat {
  Stream<ModelResponse> generate();

  Future<void> addToolResults(List<ToolExecutionResult> results);

  Future<void> addProtocolFeedback(Map<String, Object?> feedback);
}

final class InferenceToolLoopChat implements ToolLoopChat {
  InferenceToolLoopChat(this.chat, {required this.generationTimeout});

  final InferenceChat chat;
  final Duration generationTimeout;

  @override
  Stream<ModelResponse> generate() =>
      chat.generateChatResponseAsync().timeout(generationTimeout);

  @override
  Future<void> addToolResults(List<ToolExecutionResult> results) {
    return chat.addQueryChunk(
      Message.toolResponses(
        results
            .map(
              (result) => ToolResponseMessage(
                toolName: result.name,
                callId: result.id,
                response: result.toModelJson(),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<void> addProtocolFeedback(Map<String, Object?> feedback) {
    return chat.addQueryChunk(
      Message.toolResponse(toolName: 'tool_protocol', response: feedback),
    );
  }
}
