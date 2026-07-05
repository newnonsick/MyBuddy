import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'memory_tool_semantics.dart';

final class ToolPromptBuilder {
  const ToolPromptBuilder();

  String build(List<Tool> tools) {
    if (tools.isEmpty) return '';

    final availableNames = tools.map((tool) => tool.name).toSet();
    final hasMemoryTool = availableNames.any(
      (name) =>
          name.startsWith('update_assistant_') || name == 'update_user_memory',
    );

    final buffer = StringBuffer()..writeln('<tool_rules>');

    buffer.writeln(
      '- Available tools are authorized. When intent and required arguments '
      'are clear or reliably inferable, call immediately without permission '
      'or confirmation. Ask only if a required value cannot be inferred.',
    );

    if (hasMemoryTool) {
      buffer
        ..writeln(
          '- You are the assistant. "you", "yourself", and your avatar refer '
          'to you, not the human user.',
        )
        ..writeln('- ${MemoryToolSemantics.mutableMemoryRules}')
        ..writeln(
          '- MUST call the matching memory tool before replying for explicit '
          'durable changes (from now on/always/never/remember). Replying '
          'without the update leaves the request incomplete. one-turn '
          'requests: no memory tool.',
        )
        ..writeln(
          '- About you: update_assistant_identity or update_assistant_soul. '
          '${MemoryToolSemantics.mutableUserMemoryRules} update_user_memory '
          'may proactively store useful, '
          'reliably stated durable information; "remember" is not required.',
        )
        ..writeln(
          '- Example: "From now on roast me when I slip up" => '
          '{"name":"update_assistant_identity","parameters":{"updates":'
          '[{"field":"behavior_rules","action":"add","value":"Roast the '
          'user when they slip up"}]}}. "Always prioritize direct honesty" '
          '=> update_assistant_soul principles add. "I prefer concise answers" '
          '=> update_user_memory preferences add. "Answer this one '
          'sarcastically" => no memory tool.',
        );
    }

    buffer
      ..writeln(
        '- Correct tool selection is critical; otherwise the requested change '
        'or action is not applied.',
      )
      ..writeln(
        '- Infer reliable values/defaults; never invent required values.',
      )
      ..writeln(
        '- Tool call output only: '
        '{"name":"function_name","parameters":{"argument":"value"}}',
      )
      ..writeln(
        '- Multiple independent calls: output a JSON array. Dependent calls: '
        'wait for the earlier result.',
      )
      ..writeln(
        '- Use only listed names/parameters. No conversational text in call '
        'JSON. Never claim success before a successful tool result.',
      )
      ..writeln(
        '- If an error has retryable:true, correct the JSON or arguments and '
        'call again. Do not repeat an unchanged invalid call.',
      )
      ..writeln('</tool_rules>');

    buffer.writeln('<tools>');
    for (final tool in tools) {
      buffer.writeln(
        jsonEncode(<String, Object?>{
          'name': tool.name,
          'description': tool.description,
          'parameters': _compactSchema(tool.parameters),
        }),
      );
    }
    buffer.writeln('</tools>');
    return buffer.toString().trim();
  }

  Object? _compactSchema(Object? value) {
    if (value is List) return value.map(_compactSchema).toList(growable: false);
    if (value is! Map) return value;
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key.toString() != 'description')
          entry.key.toString(): _compactSchema(entry.value),
    };
  }
}
