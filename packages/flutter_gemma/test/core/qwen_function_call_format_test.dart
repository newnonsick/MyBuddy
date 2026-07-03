import 'package:flutter_gemma/core/parsing/qwen_function_call_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not promote conversational response aliases into tool arguments',
      () {
    final call = QwenFunctionCallFormat().parse(
      '<|tool_call|>call:perform_avatar_action{'
      'animation:<escape>think<escape>,'
      'response:<escape>hello<escape>}'
      '<|/tool_call|>',
    );

    expect(call, isNotNull);
    expect(call!.args, isNot(contains('response_text')));
    expect(call.args['response'], 'hello');
  });
}
