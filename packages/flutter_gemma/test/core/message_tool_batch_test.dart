import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final responses = <ToolResponseMessage>[
    ToolResponseMessage(
      toolName: 'first',
      callId: 'c1',
      response: const <String, Object?>{
        'call_id': 'c1',
        'name': 'first',
        'status': 'success',
      },
    ),
    ToolResponseMessage(
      toolName: 'second',
      callId: 'c2',
      response: const <String, Object?>{
        'call_id': 'c2',
        'name': 'second',
        'status': 'error',
      },
    ),
  ];

  test('generic task format serializes every correlated result once', () {
    final message = Message.toolResponses(responses);

    final prompt = message.transformToChatPrompt(
      type: ModelType.qwen,
      fileType: ModelFileType.task,
    );

    expect(prompt, contains('"call_id":"c1"'));
    expect(prompt, contains('"call_id":"c2"'));
    expect(RegExp('"call_id":"c1"').allMatches(prompt), hasLength(1));
  });

  test('FunctionGemma appends one model prefix after complete batch', () {
    final message = Message.toolResponses(responses);

    final prompt = message.transformToChatPrompt(
      type: ModelType.functionGemma,
      fileType: ModelFileType.binary,
    );

    expect(functionGemmaStartResp.allMatches(prompt), hasLength(2));
    expect('$startTurn$modelPrefix'.allMatches(prompt), hasLength(1));
  });
}
