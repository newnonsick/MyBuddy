import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/model_turn_collector.dart';
import 'package:mybuddy/core/llm/tool_protocol.dart';

void main() {
  const collector = ModelTurnCollector(modelType: ModelType.qwen);

  test('flattens individual and parallel function responses', () async {
    final turn = await collector.collect(
      Stream<ModelResponse>.fromIterable(<ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
        const ParallelFunctionCallResponse(
          calls: <FunctionCallResponse>[
            FunctionCallResponse(name: 'second', args: <String, dynamic>{}),
            FunctionCallResponse(name: 'third', args: <String, dynamic>{}),
          ],
        ),
      ]),
    );

    expect((turn as ToolCallTurn).calls.map((call) => call.name), <String>[
      'first',
      'second',
      'third',
    ]);
  });

  test('parses the established multi-call JSON array', () async {
    final turn = await collector.collect(
      Stream<ModelResponse>.value(
        const TextResponse(
          '[{"name":"first","parameters":{}},'
          '{"name":"second","parameters":{}}]',
        ),
      ),
    );

    expect((turn as ToolCallTurn).calls, hasLength(2));
  });

  test('classifies incomplete tool-like output as malformed', () async {
    final turn = await collector.collect(
      Stream<ModelResponse>.value(
        const TextResponse('{"name":"create_calendar_event","parameters":'),
      ),
    );

    expect(turn, isA<MalformedToolTurn>());
  });

  test('does not return intermediate text when calls are present', () async {
    final turn = await collector.collect(
      Stream<ModelResponse>.fromIterable(<ModelResponse>[
        const TextResponse('I will do that.'),
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ]),
    );

    expect(turn, isA<ToolCallTurn>());
  });

  test('returns cleaned final text when no tool call exists', () async {
    final turn = await collector.collect(
      Stream<ModelResponse>.value(const TextResponse('Hello<|im_end|>')),
    );

    expect((turn as FinalTextTurn).text, 'Hello');
  });
}
