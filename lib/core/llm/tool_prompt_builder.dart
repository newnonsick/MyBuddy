import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

final class ToolPromptBuilder {
  const ToolPromptBuilder();

  String build(List<Tool> tools) {
    if (tools.isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln(
        'You may call zero, one, or multiple available functions without '
        'asking permission.',
      )
      ..writeln(
        'For one function, output only: '
        '{"name":"function_name","parameters":{"argument":"value"}}',
      )
      ..writeln(
        'For multiple independent functions, output only a JSON array of '
        'those objects.',
      )
      ..writeln(
        'Calls in one array must be independent. If a function is dependent '
        'on an earlier result, wait for the tool results and call it in a '
        'later response.',
      )
      ..writeln(
        'After tool results, call more functions only when needed; otherwise '
        'answer the user in plain text.',
      )
      ..writeln(
        'Infer arguments from the user request, conversation, runtime context, '
        'and documented defaults whenever they are reliable.',
      )
      ..writeln(
        'Do not ask for permission or confirmation when intent and required '
        'arguments are clear. Do not ask for optional values with defaults.',
      )
      ..writeln(
        'Ask one concise question only when a required value remains materially '
        'ambiguous and choosing could perform the wrong action.',
      )
      ..writeln(
        'Never invent a required value when context and documented defaults do '
        'not resolve it.',
      )
      ..writeln(
        'Use only listed function names and parameters. Never include '
        'conversational reply text inside function parameters. Never claim '
        'success before a successful tool result.',
      );

    if (tools.length >= 2) {
      buffer.writeln(
        'Multiple-call format example: ${jsonEncode(<Object?>[
          <String, Object?>{'name': tools[0].name, 'parameters': <String, Object?>{}},
          <String, Object?>{'name': tools[1].name, 'parameters': <String, Object?>{}},
        ])}',
      );
    }

    buffer.writeln('<tool_code>');
    for (final tool in tools) {
      buffer.writeln(
        jsonEncode(<String, Object?>{
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
        }),
      );
    }
    buffer.writeln('</tool_code>');
    return buffer.toString().trim();
  }
}
