import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

enum ToolResultErrorCode {
  unknownTool,
  unavailableTool,
  invalidArguments,
  executionFailed,
  timedOut,
  duplicateCall,
}

final class ToolArgumentException implements Exception {
  const ToolArgumentException(this.message);

  final String message;
}

final class ToolExecutionException implements Exception {
  const ToolExecutionException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;
}

final class ToolInvocation {
  ToolInvocation({
    required this.id,
    required this.name,
    required Map<String, dynamic> arguments,
  }) : arguments = Map<String, dynamic>.unmodifiable(arguments);

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  String get canonicalSignature => '$name:${_canonicalJson(arguments)}';
}

final class ToolExecutionResult {
  const ToolExecutionResult.success({
    required this.id,
    required this.name,
    required this.data,
    this.cached = false,
  }) : errorCode = null,
       message = null,
       retryable = false;

  const ToolExecutionResult.failure({
    required this.id,
    required this.name,
    required ToolResultErrorCode code,
    required this.message,
    this.retryable = false,
    this.cached = false,
  }) : data = const <String, Object?>{},
       errorCode = code;

  final String id;
  final String name;
  final Map<String, Object?> data;
  final ToolResultErrorCode? errorCode;
  final String? message;
  final bool retryable;
  final bool cached;

  bool get isSuccess => errorCode == null;

  Map<String, Object?> toModelJson() => <String, Object?>{
    'call_id': id,
    'name': name,
    'status': isSuccess ? 'success' : 'error',
    if (isSuccess) 'data': data,
    if (!isSuccess)
      'error': <String, Object?>{
        'code': errorCode!.name,
        'message': message,
        'retryable': retryable,
      },
    if (cached) 'cached': true,
  };

  ToolExecutionResult copyForDuplicate({required String id}) => isSuccess
      ? ToolExecutionResult.success(
          id: id,
          name: name,
          data: data,
          cached: true,
        )
      : ToolExecutionResult.failure(
          id: id,
          name: name,
          code: errorCode!,
          message: message ?? 'Tool execution failed.',
          retryable: retryable,
          cached: true,
        );
}

sealed class ModelTurn {
  const ModelTurn();
}

final class FinalTextTurn extends ModelTurn {
  const FinalTextTurn(this.text);

  final String text;
}

final class ToolCallTurn extends ModelTurn {
  ToolCallTurn(List<FunctionCallResponse> calls)
    : calls = List<FunctionCallResponse>.unmodifiable(calls);

  final List<FunctionCallResponse> calls;
}

final class MalformedToolTurn extends ModelTurn {
  const MalformedToolTurn(this.reason);

  final String reason;
}

final class EmptyTurn extends ModelTurn {
  const EmptyTurn();
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
