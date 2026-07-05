import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/llm/memory_tool_semantics.dart';

void main() {
  test('defines assistant self-reference and persistent change rules', () {
    expect(MemoryToolSemantics.selfReference, contains('currently speaking'));
    expect(MemoryToolSemantics.selfReference, contains('yourself'));
    expect(MemoryToolSemantics.persistenceRules, contains('from now on'));
    expect(MemoryToolSemantics.persistenceRules, contains('one-turn'));
    expect(MemoryToolSemantics.mutableMemoryRules, contains('mutable memory'));
    expect(MemoryToolSemantics.mutableMemoryRules, contains('supersedes'));
    expect(MemoryToolSemantics.mutableMemoryRules, contains('never defend'));
    expect(MemoryToolSemantics.mutableUserMemoryRules, contains('USER'));
    expect(MemoryToolSemantics.mutableUserMemoryRules, contains('mutable'));
    expect(
      MemoryToolSemantics.mutableUserMemoryRules,
      contains('newer user statements supersede'),
    );
  });

  test('routes every existing memory field exactly once', () {
    expect(MemoryToolSemantics.soulFields.keys, {
      'mission',
      'principles',
      'boundaries',
      'response_style',
    });
    expect(MemoryToolSemantics.identityFields.keys, {
      'assistant_name',
      'role',
      'voice',
      'behavior_rules',
    });
    expect(MemoryToolSemantics.userFields.keys, {
      'name',
      'traits',
      'preferences',
      'goals',
      'facts',
    });
    expect(
      MemoryToolSemantics.identityFields['behavior_rules'],
      contains('conditional conduct'),
    );
  });

  test('examples separate durable changes from one-turn requests', () {
    final examples = MemoryToolSemantics.examples.join('\n');
    expect(examples, contains('From now on'));
    expect(examples, contains('update_assistant_identity'));
    expect(examples, contains('Answer only this message sarcastically'));
    expect(examples, contains('no memory tool'));
  });

  test('allows proactive user memory without confirmation', () {
    expect(
      MemoryToolSemantics.updateUserMemoryDescription,
      contains('Proactively store'),
    );
    expect(
      MemoryToolSemantics.updateUserMemoryDescription,
      contains('"Remember" is not required'),
    );
    expect(
      MemoryToolSemantics.updateUserMemoryDescription,
      contains('without asking permission or confirmation'),
    );
  });
}
