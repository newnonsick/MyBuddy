import 'dart:collection';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:mybuddy/core/llm/tool_loop_chat.dart';
import 'package:mybuddy/core/llm/tool_protocol.dart';

final class FakeToolLoopChat implements ToolLoopChat {
  FakeToolLoopChat(Iterable<List<ModelResponse>> turns)
    : turns = Queue<List<ModelResponse>>.of(turns);

  final Queue<List<ModelResponse>> turns;
  final List<List<ToolExecutionResult>> resultBatches =
      <List<ToolExecutionResult>>[];
  final List<Map<String, Object?>> protocolFeedback = <Map<String, Object?>>[];

  @override
  Stream<ModelResponse> generate() {
    if (turns.isEmpty) throw StateError('No scripted model turn.');
    return Stream<ModelResponse>.fromIterable(turns.removeFirst());
  }

  @override
  Future<void> addToolResults(List<ToolExecutionResult> results) async {
    resultBatches.add(List<ToolExecutionResult>.unmodifiable(results));
  }

  @override
  Future<void> addProtocolFeedback(Map<String, Object?> feedback) async {
    protocolFeedback.add(Map<String, Object?>.unmodifiable(feedback));
  }
}
