import 'dart:convert';

import 'package:flutter_gemma/core/model_response.dart';

import 'function_call_format.dart';
import 'json_function_call_format.dart';
import 'json_parsing_utils.dart';

/// Qwen/Mistral tool call format.
///
/// Primary format: `<tool_call>{"name":"...","arguments":{...}}</tool_call>`
/// Falls back to JSON formats (tool_code, markdown, direct JSON).
///
/// Used by: ModelType.qwen
class QwenFunctionCallFormat extends FunctionCallFormat {
  final _jsonFallback = JsonFunctionCallFormat();

  @override
  bool isFunctionCallStart(String buffer) {
    final clean = buffer.trim();
    if (clean.isEmpty) return false;

    return clean.startsWith('<tool_call>') ||
        clean.startsWith('<|tool_call') ||
        _jsonFallback.isFunctionCallStart(buffer);
  }

  @override
  bool isDefinitelyText(String buffer) {
    final clean = buffer.trim();
    if (clean.length < 5) return false;

    if (isFunctionCallStart(buffer)) return false;

    final early = clean.length > 30 ? clean.substring(0, 30) : clean;
    return !early.contains('{') &&
        !early.toLowerCase().contains('json') &&
        !early.contains('<tool');
  }

  @override
  bool isFunctionCallComplete(String buffer) {
    final clean = buffer.trim();
    if (clean.isEmpty) return false;

    if (clean.contains('<tool_call>') && clean.contains('</tool_call>')) {
      return true;
    }
    if (clean.contains('<|tool_call') &&
        (clean.contains('<|/tool_call|>') ||
            clean.contains('<tool_call|>') ||
            clean.contains('<|im_end|>') ||
            clean.endsWith('}'))) {
      return true;
    }
    return _jsonFallback.isFunctionCallComplete(buffer);
  }

  @override
  FunctionCallResponse? parse(String text) {
    if (text.trim().isEmpty) return null;
    final content = JsonParsingUtils.cleanModelResponse(text);

    return _parseToolCallBlock(content) ??
        _parseQwenSpecialToolCall(content) ??
        _jsonFallback.parse(text);
  }

  @override
  List<FunctionCallResponse> parseAll(String text) {
    if (text.trim().isEmpty) return [];
    final content = JsonParsingUtils.cleanModelResponse(text);

    final results = <FunctionCallResponse>[];
    final regex =
        RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>', multiLine: true);
    for (final match in regex.allMatches(content)) {
      final result = JsonParsingUtils.parseJsonString(match.group(1)!.trim());
      if (result != null) results.add(result);
    }
    if (results.isNotEmpty) return results;

    final specialResults = _parseAllQwenSpecialToolCalls(content);
    if (specialResults.isNotEmpty) return specialResults;

    return _jsonFallback.parseAll(text);
  }

  /// Parse `<tool_call>JSON</tool_call>` format.
  FunctionCallResponse? _parseToolCallBlock(String content) {
    final regex =
        RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>', multiLine: true);
    final match = regex.firstMatch(content);

    if (match != null) {
      final jsonStr = match.group(1)!.trim();
      return JsonParsingUtils.parseJsonString(jsonStr);
    }
    return null;
  }

  FunctionCallResponse? _parseQwenSpecialToolCall(String content) {
    final calls = _parseAllQwenSpecialToolCalls(content);
    if (calls.isEmpty) return null;
    return calls.first;
  }

  List<FunctionCallResponse> _parseAllQwenSpecialToolCalls(String content) {
    final results = <FunctionCallResponse>[];
    final blockRegex = RegExp(
      r'<\|tool_call\|?>\s*([\s\S]*?)(?:<\|/tool_call\|>|<tool_call\|>|<\|im_end\|>|$)',
      multiLine: true,
    );

    for (final match in blockRegex.allMatches(content)) {
      final body = match.group(1)?.trim() ?? '';
      final call = _parseQwenSpecialBody(body);
      if (call != null) results.add(call);
    }
    return results;
  }

  FunctionCallResponse? _parseQwenSpecialBody(String body) {
    if (body.isEmpty) return null;

    if (body.startsWith('{')) {
      final direct = JsonParsingUtils.parseJsonString(body);
      if (direct != null) return direct;
    }

    final callMatch = RegExp(
      r'call:([A-Za-z_][A-Za-z0-9_]*)\s*([\s\S]*)$',
      multiLine: true,
    ).firstMatch(body);
    if (callMatch == null) return null;

    final name = _normalizeFunctionName(callMatch.group(1)!);
    final rest = (callMatch.group(2) ?? '').trim();
    return FunctionCallResponse(name: name, args: _parseQwenSpecialArgs(rest));
  }

  Map<String, dynamic> _parseQwenSpecialArgs(String rawArgs) {
    final trimmed = rawArgs.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};

    final jsonText =
        _extractJsonObject(trimmed) ?? _extractArgumentsJson(trimmed);
    if (jsonText != null) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map<String, dynamic>) {
          final args = decoded['arguments'] ?? decoded['parameters'];
          if (args is Map<String, dynamic>) return _normalizeArgs(args);
          return _normalizeArgs(decoded);
        }
      } catch (_) {}
    }

    final params = <String, dynamic>{};
    final escapedParamRegex = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*):<escape>([\s\S]*?)<escape>',
    );
    for (final match in escapedParamRegex.allMatches(trimmed)) {
      params[_normalizeArgName(match.group(1)!)] = _normalizeArgValue(
        match.group(2)!,
      );
    }
    if (params.isNotEmpty) return params;

    final simpleParamRegex = RegExp(
      r'''([A-Za-z_][A-Za-z0-9_]*)\s*:\s*("[^"]*"|'[^']*'|[^,}\n]+)''',
    );
    for (final match in simpleParamRegex.allMatches(trimmed)) {
      var value = match.group(2)!.trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      params[_normalizeArgName(match.group(1)!)] = _normalizeArgValue(value);
    }
    return params;
  }

  String _normalizeFunctionName(String name) {
    return switch (name.trim()) {
      'function_avatar_action' => 'perform_avatar_action',
      'avatar_action' => 'perform_avatar_action',
      _ => name.trim(),
    };
  }

  Map<String, dynamic> _normalizeArgs(Map<String, dynamic> raw) {
    return raw.map(
      (key, value) => MapEntry(
        _normalizeArgName(key),
        value is String ? _normalizeArgValue(value) : value,
      ),
    );
  }

  String _normalizeArgName(String name) {
    return name.trim();
  }

  dynamic _normalizeArgValue(String value) {
    var normalized = value.trim();
    normalized = normalized.replaceAll('<|"|>', '');
    normalized = normalized.replaceAll('<|\'|>', '');
    normalized = normalized.replaceAll('<escape>', '');
    if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
        (normalized.startsWith("'") && normalized.endsWith("'"))) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    normalized = normalized.trim();
    final intValue = int.tryParse(normalized);
    if (intValue != null) return intValue;
    final lower = normalized.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    return normalized;
  }

  String? _extractArgumentsJson(String text) {
    final match = RegExp(
      r'(?:arguments|parameters)\s*:\s*(\{[\s\S]*\})',
      multiLine: true,
    ).firstMatch(text);
    return match?.group(1);
  }

  String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaping = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (char == '\\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }
}
