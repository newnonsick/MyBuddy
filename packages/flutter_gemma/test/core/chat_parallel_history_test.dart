import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stream history retains every emitted tool call', () async {
    final session = _FakeSession(<String>[
      '<tool_call>{"name":"first","arguments":{',
      '}}</tool_call>',
      '<tool_call>{"name":"second","arguments":{}}</tool_call>',
    ]);
    final chat = InferenceChat(
      sessionCreator: () async => session,
      maxTokens: 4096,
      tools: const <Tool>[
        Tool(name: 'first', description: 'first'),
        Tool(name: 'second', description: 'second'),
      ],
      supportsFunctionCalls: true,
      modelType: ModelType.qwen,
      fileType: ModelFileType.task,
    );
    await chat.initSession();

    final responses = await chat.generateChatResponseAsync().toList();

    expect(responses.whereType<FunctionCallResponse>(), hasLength(2));
    expect(chat.fullHistory.last.text, contains('"name":"first"'));
    expect(chat.fullHistory.last.text, contains('"name":"second"'));
  });
}

final class _FakeSession implements InferenceModelSession {
  _FakeSession(this.tokens);

  final List<String> tokens;

  @override
  Future<void> addQueryChunk(Message message) async {}

  @override
  Future<void> close() async {}

  @override
  Future<String> getResponse() async => tokens.join();

  @override
  Stream<String> getResponseAsync() => Stream<String>.fromIterable(tokens);

  @override
  Future<int> sizeInTokens(String text) async => text.length;

  @override
  Future<void> stopGeneration() async {}
}
