import 'package:flutter_gemma/flutter_gemma.dart';

final class PromptBudgetAssessment {
  const PromptBudgetAssessment({
    required this.inputTokens,
    required this.inputLimit,
    required this.effectiveTokenBuffer,
  });

  final int inputTokens;
  final int inputLimit;
  final int effectiveTokenBuffer;

  bool get fits => inputTokens <= inputLimit;
}

final class PromptBudgeter {
  const PromptBudgeter({this.templateSafetyTokens = 64});

  final int templateSafetyTokens;

  int effectiveTokenBuffer({
    required int maxTokens,
    required int configuredTokenBuffer,
  }) {
    if (configuredTokenBuffer == maxTokens - 512) return 512;
    return configuredTokenBuffer.clamp(1, maxTokens - 1);
  }

  Future<PromptBudgetAssessment> assess({
    required InferenceModelSession session,
    required int maxTokens,
    required int configuredTokenBuffer,
    required String systemText,
    required Iterable<Message> history,
    required String userText,
  }) async {
    final effectiveBuffer = effectiveTokenBuffer(
      maxTokens: maxTokens,
      configuredTokenBuffer: configuredTokenBuffer,
    );
    var inputTokens = templateSafetyTokens;
    inputTokens += await session.sizeInTokens(systemText);
    inputTokens += await session.sizeInTokens(userText);
    for (final message in history) {
      inputTokens += await session.sizeInTokens(message.text);
      inputTokens += 4;
    }
    return PromptBudgetAssessment(
      inputTokens: inputTokens,
      inputLimit: maxTokens - effectiveBuffer,
      effectiveTokenBuffer: effectiveBuffer,
    );
  }
}
