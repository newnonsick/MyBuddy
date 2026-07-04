import 'package:flutter_gemma/flutter_gemma.dart';

import '../../shared/utils/json_extractor.dart';
import 'tool_protocol.dart';
import 'package:flutter/foundation.dart';

final class ModelTurnCollector {
  const ModelTurnCollector({required this.modelType});

  final ModelType modelType;

  Future<ModelTurn> collect(Stream<ModelResponse> responses) async {
    final text = StringBuffer();
    final calls = <FunctionCallResponse>[];

    await for (final response in responses) {
      debugPrint('ModelTurnCollector: received response: $response');
      switch (response) {
        case TextResponse(:final token):
          text.write(token);
        case FunctionCallResponse():
          calls.add(response);
        case ParallelFunctionCallResponse(calls: final parallelCalls):
          calls.addAll(parallelCalls);
        case ThinkingResponse():
          break;
      }
    }

    if (calls.isNotEmpty) return ToolCallTurn(calls);

    final rawText = text.toString();
    final parsed = FunctionCallParser.parseAll(rawText, modelType: modelType);
    if (parsed.isNotEmpty) return ToolCallTurn(parsed);

    final fallbackCalls = <FunctionCallResponse>[];
    for (final block in extractJsonBlocks(rawText)) {
      final call = FunctionCallParser.parse(block, modelType: modelType);
      if (call != null) fallbackCalls.add(call);
    }
    if (fallbackCalls.isNotEmpty) return ToolCallTurn(fallbackCalls);

    final cleaned = _cleanText(rawText);
    if (cleaned.isEmpty) return const EmptyTurn();
    if (_looksLikeToolCall(cleaned)) {
      return const MalformedToolTurn('invalid_tool_format');
    }
    return FinalTextTurn(cleaned);
  }

  bool _looksLikeToolCall(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('<tool_call') || lower.contains('<|tool_call')) {
      return true;
    }
    final trimmed = text.trimLeft();
    final startsStructured = trimmed.startsWith('{') || trimmed.startsWith('[');
    return startsStructured &&
        lower.contains('"name"') &&
        (lower.contains('"parameters"') || lower.contains('"arguments"'));
  }

  String _cleanText(String text) => text
      .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
      .replaceAll(RegExp(r'<end_of_turn>\s*$'), '')
      .replaceAll(RegExp(r'<\|im_end\|>\s*$'), '')
      .replaceAll(r'\n', '\n')
      .trim();
}
