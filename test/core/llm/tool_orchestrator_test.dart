import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/llm_errors.dart';
import 'package:mybuddy/core/llm/model_turn_collector.dart';
import 'package:mybuddy/core/llm/tool_orchestrator.dart';
import 'package:mybuddy/core/llm/tool_registry.dart';

import 'fakes/fake_tool_loop_chat.dart';

void main() {
  const collector = ModelTurnCollector(modelType: ModelType.qwen);

  test('executes a complete batch before returning final text', () async {
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const ParallelFunctionCallResponse(
          calls: <FunctionCallResponse>[
            FunctionCallResponse(name: 'slow', args: <String, dynamic>{}),
            FunctionCallResponse(name: 'fast', args: <String, dynamic>{}),
          ],
        ),
      ],
      <ModelResponse>[const TextResponse('Finished.')],
    ]);
    final snapshot = await _snapshot(<ToolBinding>[
      ToolBinding(
        definition: const Tool(name: 'slow', description: 'slow'),
        execute: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return <String, Object?>{'value': 'slow'};
        },
      ),
      ToolBinding(
        definition: const Tool(name: 'fast', description: 'fast'),
        execute: (_) async => <String, Object?>{'value': 'fast'},
      ),
    ]);

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: snapshot,
      runIdFactory: () => 'run',
    ).run();

    expect(response, 'Finished.');
    expect(chat.resultBatches, hasLength(1));
    expect(chat.resultBatches.single.map((result) => result.name), <String>[
      'slow',
      'fast',
    ]);
  });

  test('supports compositional tool rounds', () async {
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ],
      <ModelResponse>[
        const FunctionCallResponse(name: 'second', args: <String, dynamic>{}),
      ],
      <ModelResponse>[const TextResponse('Both complete.')],
    ]);
    final snapshot = await _snapshot(<ToolBinding>[
      _binding('first'),
      _binding('second'),
    ]);

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: snapshot,
    ).run();

    expect(response, 'Both complete.');
    expect(chat.resultBatches, hasLength(2));
  });

  test('deduplicates identical calls across rounds', () async {
    var executionCount = 0;
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const FunctionCallResponse(
          name: 'side_effect',
          args: <String, dynamic>{'value': 'same'},
        ),
      ],
      <ModelResponse>[
        const FunctionCallResponse(
          name: 'side_effect',
          args: <String, dynamic>{'value': 'same'},
        ),
      ],
      <ModelResponse>[const TextResponse('Done.')],
    ]);
    final snapshot = await _snapshot(<ToolBinding>[
      ToolBinding(
        definition: const Tool(name: 'side_effect', description: 'effect'),
        execute: (_) async {
          executionCount++;
          return <String, Object?>{'ok': true};
        },
      ),
    ]);

    await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: snapshot,
    ).run();

    expect(executionCount, 1);
    expect(chat.resultBatches.last.single.cached, isTrue);
  });

  test('repairs malformed output then continues', () async {
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[const TextResponse('{"name":"first","parameters":')],
      <ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ],
      <ModelResponse>[const TextResponse('Recovered.')],
    ]);

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: await _snapshot(<ToolBinding>[_binding('first')]),
    ).run();

    expect(response, 'Recovered.');
    expect(chat.protocolFeedback.single['code'], 'invalid_tool_format');
  });

  test('two malformed turns force one plain-text finalization', () async {
    final malformed = <ModelResponse>[
      const TextResponse('{"name":"first","parameters":'),
    ];
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      malformed,
      malformed,
      <ModelResponse>[const TextResponse('Could not use the tool.')],
    ]);

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: await _snapshot(<ToolBinding>[_binding('first')]),
    ).run();

    expect(response, 'Could not use the tool.');
    expect(chat.protocolFeedback.last['tools_disabled'], isTrue);
  });

  test('rejects tool calls emitted during forced finalization', () async {
    final malformed = <ModelResponse>[
      const TextResponse('{"name":"first","parameters":'),
    ];
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      malformed,
      malformed,
      <ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ],
    ]);

    await expectLater(
      ToolOrchestrator(
        chat: chat,
        collector: collector,
        tools: await _snapshot(<ToolBinding>[_binding('first')]),
      ).run(),
      throwsA(
        isA<LlmRuntimeException>().having(
          (error) => error.code,
          'code',
          LlmErrorCode.toolProtocolFailed,
        ),
      ),
    );
  });

  test('partial failure does not cancel other calls in a batch', () async {
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const ParallelFunctionCallResponse(
          calls: <FunctionCallResponse>[
            FunctionCallResponse(name: 'fails', args: <String, dynamic>{}),
            FunctionCallResponse(name: 'works', args: <String, dynamic>{}),
          ],
        ),
      ],
      <ModelResponse>[const TextResponse('Handled partial failure.')],
    ]);
    final snapshot = await _snapshot(<ToolBinding>[
      ToolBinding(
        definition: const Tool(name: 'fails', description: 'fails'),
        execute: (_) async => throw StateError('private failure'),
      ),
      _binding('works'),
    ]);

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: snapshot,
    ).run();

    expect(response, 'Handled partial failure.');
    expect(chat.resultBatches.single.map((result) => result.isSuccess), <bool>[
      false,
      true,
    ]);
  });

  test(
    'repeated invalid calls finalize before progressing round limit',
    () async {
      final invalidCall = <ModelResponse>[
        const FunctionCallResponse(
          name: 'needs_value',
          args: <String, dynamic>{},
        ),
      ];
      final chat = FakeToolLoopChat(<List<ModelResponse>>[
        invalidCall,
        invalidCall,
        <ModelResponse>[const TextResponse('Please provide a value.')],
      ]);
      final snapshot = await _snapshot(<ToolBinding>[
        ToolBinding(
          definition: const Tool(
            name: 'needs_value',
            description: 'needs value',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'value': <String, dynamic>{'type': 'string'},
              },
              'required': <String>['value'],
            },
          ),
          execute: (_) async => <String, Object?>{'ok': true},
        ),
      ]);

      final response = await ToolOrchestrator(
        chat: chat,
        collector: collector,
        tools: snapshot,
      ).run();

      expect(response, 'Please provide a value.');
      expect(chat.resultBatches, hasLength(2));
      expect(chat.protocolFeedback.last['tools_disabled'], isTrue);
    },
  );

  test('requested call budget prevents oversized batch execution', () async {
    var executions = 0;
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const ParallelFunctionCallResponse(
          calls: <FunctionCallResponse>[
            FunctionCallResponse(name: 'one', args: <String, dynamic>{}),
            FunctionCallResponse(name: 'two', args: <String, dynamic>{}),
          ],
        ),
      ],
      <ModelResponse>[const TextResponse('Too many actions requested.')],
    ]);
    final bindings = <ToolBinding>[
      for (final name in <String>['one', 'two'])
        ToolBinding(
          definition: Tool(name: name, description: name),
          execute: (_) async {
            executions++;
            return <String, Object?>{'ok': true};
          },
        ),
    ];

    final response = await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: await _snapshot(bindings),
      maxRequestedCalls: 1,
    ).run();

    expect(response, 'Too many actions requested.');
    expect(executions, 0);
  });

  test('terminal failure discloses possible completed actions', () async {
    final malformed = <ModelResponse>[
      const TextResponse('{"name":"first","parameters":'),
    ];
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ],
      malformed,
      malformed,
      <ModelResponse>[
        const FunctionCallResponse(name: 'first', args: <String, dynamic>{}),
      ],
    ]);

    await expectLater(
      ToolOrchestrator(
        chat: chat,
        collector: collector,
        tools: await _snapshot(<ToolBinding>[_binding('first')]),
      ).run(),
      throwsA(
        isA<LlmRuntimeException>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('Some requested actions may already have completed.'),
        ),
      ),
    );
  });

  test('emits privacy-safe tool diagnostics', () async {
    final diagnostics = <({String stage, String? tool, String? error})>[];
    final chat = FakeToolLoopChat(<List<ModelResponse>>[
      <ModelResponse>[
        const FunctionCallResponse(
          name: 'remember',
          args: <String, dynamic>{'private_value': 'must not be logged'},
        ),
      ],
      <ModelResponse>[const TextResponse('Done.')],
    ]);

    await ToolOrchestrator(
      chat: chat,
      collector: collector,
      tools: await _snapshot(<ToolBinding>[_binding('remember')]),
      runIdFactory: () => 'run',
      diagnosticSink:
          ({
            required runId,
            required round,
            required stage,
            toolName,
            errorCode,
          }) {
            diagnostics.add((stage: stage, tool: toolName, error: errorCode));
          },
    ).run();

    expect(diagnostics.map((item) => item.stage), <String>[
      'tool_requested',
      'tool_completed',
      'final_text',
    ]);
    expect(diagnostics[0].tool, 'remember');
    expect(diagnostics[1].error, isNull);
    expect(diagnostics.toString(), isNot(contains('must not be logged')));
  });
}

ToolBinding _binding(String name) => ToolBinding(
  definition: Tool(name: name, description: name),
  execute: (_) async => <String, Object?>{'ok': true},
);

Future<ToolRegistrySnapshot> _snapshot(List<ToolBinding> bindings) {
  return ToolRegistry(bindings).snapshot();
}
