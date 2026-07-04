import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

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

    if (hasMemoryTool) {
      buffer
        ..writeln(
          '- You are the assistant. "you", "yourself", and your avatar refer '
          'to you, not the human user.',
        )
        ..writeln(
          '- MUST call the matching memory tool for explicit durable changes '
          '(from now on/always/never/remember). one-turn requests: no memory tool.',
        )
        ..writeln(
          '- About you: update_assistant_identity or update_assistant_soul. '
          'About the human: update_user_memory.',
        )
        ..writeln(
          '- Example: "From now on roast me when I slip up" => '
          '{"name":"update_assistant_identity","parameters":{"updates":'
          '[{"field":"behavior_rules","action":"add","value":"Roast the '
          'user when they slip up"}]}}. "Answer this one sarcastically" => '
          'no memory tool.',
        );
    }

    buffer
      ..writeln(
        '- Correct tool selection is critical; otherwise the requested change '
        'or action is not applied.',
      )
      ..writeln(
        '- Clear action with required arguments: call without confirmation. '
        'Infer reliable values/defaults; never invent required values.',
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
