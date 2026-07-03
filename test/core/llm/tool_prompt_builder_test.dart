import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/calendar_event_tool.dart';
import 'package:mybuddy/core/llm/tool_prompt_builder.dart';

void main() {
  const builder = ToolPromptBuilder();

  test('keeps single-object format and documents multiple calls', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'first', description: 'First tool'),
      Tool(name: 'second', description: 'Second tool'),
    ]);

    expect(
      prompt,
      contains('{"name":"function_name","parameters":{"argument":"value"}}'),
    );
    expect(prompt, contains('[{"name":"first","parameters":{}}'));
    expect(prompt, contains('zero, one, or multiple'));
    expect(prompt, isNot(contains('only 1 function')));
    expect(prompt, isNot(contains('response_text')));
  });

  test('requires dependent calls to wait for results', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'first', description: 'First tool'),
    ]);

    expect(prompt, contains('dependent'));
    expect(prompt, contains('later response'));
  });

  test('returns empty instruction when no tools are available', () {
    expect(builder.build(const <Tool>[]), isEmpty);
  });

  test('prefers inference and defaults over unnecessary questions', () {
    final prompt = builder.build(<Tool>[CalendarEventTool.definition]);

    expect(prompt, contains('Infer arguments from the user request'));
    expect(prompt, contains('Do not ask for permission or confirmation'));
    expect(prompt, contains('Do not ask for optional values with defaults'));
    expect(prompt, contains('Ask one concise question only'));
    expect(prompt, contains('Never invent a required value'));
    expect(prompt, contains('Timed example parameters'));
    expect(prompt, contains('all-day'));
    expect(prompt, isNot(contains('start_date')));
    expect(prompt, isNot(contains('end_date')));
  });
}
