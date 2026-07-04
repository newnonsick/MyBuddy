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
    expect(prompt, contains('Multiple independent calls'));
    expect(prompt, isNot(contains('response_text')));
  });

  test('requires dependent calls to wait for results', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'first', description: 'First tool'),
    ]);

    expect(prompt, contains('dependent'));
    expect(prompt, contains('wait for the earlier result'));
  });

  test('returns empty instruction when no tools are available', () {
    expect(builder.build(const <Tool>[]), isEmpty);
  });

  test('prefers inference and defaults over unnecessary questions', () {
    final prompt = builder.build(<Tool>[CalendarEventTool.definition]);

    expect(prompt, contains('Infer reliable values/defaults'));
    expect(prompt, contains('call without confirmation'));
    expect(prompt, contains('never invent required values'));
    expect(prompt, contains('Timed example parameters'));
    expect(prompt, contains('all-day'));
    expect(prompt, isNot(contains('start_date')));
    expect(prompt, isNot(contains('end_date')));
  });

  test('requires tools for explicit persistent changes', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'update_assistant_identity', description: 'identity'),
      Tool(name: 'update_user_memory', description: 'user'),
    ]);

    expect(prompt, contains('You are the assistant'));
    expect(prompt, contains('MUST call'));
    expect(prompt, contains('from now on'));
    expect(prompt, contains('one-turn'));
    expect(prompt, contains('Never claim success'));
  });

  test('includes compact durable and non-durable examples', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'update_assistant_identity', description: 'identity'),
    ]);

    expect(prompt, contains('roast me when I slip up'));
    expect(prompt, contains('no memory tool'));
  });

  test('does not advertise unavailable memory tools', () {
    final prompt = builder.build(const <Tool>[
      Tool(name: 'perform_avatar_action', description: 'avatar'),
    ]);

    expect(prompt, isNot(contains('update_assistant_identity')));
    expect(prompt, isNot(contains('update_assistant_soul')));
    expect(prompt, isNot(contains('update_user_memory')));
    expect(prompt, isNot(contains('from now on')));
  });

  test('compacts nested schemas without losing constraints', () {
    final prompt = builder.build(const <Tool>[
      Tool(
        name: 'sample',
        description: 'Top-level purpose',
        parameters: <String, dynamic>{
          'type': 'object',
          'description': 'Remove this prose',
          'properties': <String, dynamic>{
            'mode': <String, dynamic>{
              'type': 'string',
              'description': 'Remove this too',
              'enum': <String>['a', 'b'],
            },
          },
          'required': <String>['mode'],
        },
      ),
    ]);

    expect(prompt, contains('Top-level purpose'));
    expect(prompt, contains('"enum":["a","b"]'));
    expect(prompt, contains('"required":["mode"]'));
    expect(prompt, isNot(contains('Remove this')));
  });
}
