enum LlmErrorCode {
  modelUnavailable,
  activationFailed,
  generationTimedOut,
  generationInterrupted,
  inputTooLong,
  toolFailed,
  memoryFailed,
  toolProtocolFailed,
  toolLoopLimitReached,
  closed,
}

final class LlmRuntimeException implements Exception {
  const LlmRuntimeException(this.code, this.userMessage, {this.cause});

  final LlmErrorCode code;
  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}
