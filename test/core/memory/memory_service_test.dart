import 'package:flutter_test/flutter_test.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = MemoryService();
  });

  test('loadMemoryData migrates aggregate memory without deadlock', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MemoryStorageKeys.memory: const UserMemory(
        user: UserProfileMemory(name: 'Ada'),
      ).toJsonString(),
    });
    service = MemoryService();

    final memory = await service.loadMemoryData().timeout(
      const Duration(seconds: 1),
    );

    expect(memory.user.name, 'Ada');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(MemoryStorageKeys.userMemory), true);
  });

  test(
    'loadMemory returns pretty json without nested queue deadlock',
    () async {
      await service.saveMemoryData(
        const UserMemory(user: UserProfileMemory(name: 'Grace')),
      );

      final raw = await service.loadMemory().timeout(
        const Duration(seconds: 1),
      );

      expect(raw, contains('Grace'));
    },
  );

  test('saveMemory handles blank and raw text without deadlock', () async {
    await service.saveMemory('').timeout(const Duration(seconds: 1));
    var memory = await service.loadMemoryData();
    expect(memory.isEmpty, true);

    await service
        .saveMemory('likes local models')
        .timeout(const Duration(seconds: 1));
    memory = await service.loadMemoryData();
    expect(memory.user.facts, contains('likes local models'));
  });

  test('applyMemoryPatches validates and merges user memory', () async {
    final result = await service.applyMemoryPatches(const <MemoryPatch>[
      MemoryPatch(
        section: 'user',
        field: 'name',
        action: MemoryPatchActions.set,
        value: 'Ada',
      ),
      MemoryPatch(
        section: 'user',
        field: 'preferences',
        action: MemoryPatchActions.add,
        value: 'prefers concise answers',
      ),
      MemoryPatch(
        section: 'user',
        field: 'unknown',
        action: MemoryPatchActions.add,
        value: 'ignored',
      ),
    ]);

    expect(result.success, true);
    final memory = await service.loadMemoryData();
    expect(memory.user.name, 'Ada');
    expect(memory.user.preferences, contains('prefers concise answers'));
  });

  test(
    'updateMemoryFromToolCall applies memory args without extraction',
    () async {
      final result = await service.updateMemoryFromToolCall(
        toolName: 'update_user_memory',
        args: <String, dynamic>{
          'response_text': 'I will remember that.',
          'updates': <Map<String, dynamic>>[
            <String, dynamic>{
              'field': 'goals',
              'action': 'add',
              'value': 'ship production-grade Flutter apps',
            },
          ],
        },
      );

      expect(result.success, true);
      final memory = await service.loadMemoryData();
      expect(memory.user.goals, contains('ship production-grade Flutter apps'));
    },
  );

  test('updateMemoryFromToolCall respects locked soul fields', () async {
    await service.saveMemoryData(
      const UserMemory(soul: SoulMemory(mission: 'Original mission')),
    );
    await service.saveSoulLockedFields(<String>{MemoryFieldPaths.soulMission});

    final result = await service.updateMemoryFromToolCall(
      toolName: 'update_assistant_soul',
      args: <String, dynamic>{
        'response_text': 'I will keep that in mind.',
        'updates': <Map<String, dynamic>>[
          <String, dynamic>{
            'field': 'mission',
            'action': 'set',
            'value': 'New mission',
          },
          <String, dynamic>{
            'field': 'principles',
            'action': 'add',
            'value': 'Be practical',
          },
        ],
      },
    );

    expect(result.success, true);
    final memory = await service.loadMemoryData();
    expect(memory.soul.mission, 'Original mission');
    expect(memory.soul.principles, contains('Be practical'));
  });

  test('reports applied locked invalid and no-effect patches', () async {
    await service.saveMemoryData(
      const UserMemory(identity: IdentityMemory(voice: <String>['Direct'])),
    );
    await service.saveIdentityLockedFields(<String>{
      MemoryFieldPaths.identityAssistantName,
    });

    final result = await service.applyMemoryPatches(const <MemoryPatch>[
      MemoryPatch(
        section: 'identity',
        field: 'voice',
        action: 'add',
        value: 'Playful',
      ),
      MemoryPatch(
        section: 'identity',
        field: 'assistant_name',
        action: 'set',
        value: 'Nova',
      ),
      MemoryPatch(
        section: 'identity',
        field: 'unknown',
        action: 'add',
        value: 'x',
      ),
      MemoryPatch(
        section: 'identity',
        field: 'voice',
        action: 'add',
        value: 'Direct',
      ),
    ]);

    expect(result.status, MemoryUpdateStatus.partial);
    expect(result.appliedCount, 1);
    expect(
      result.rejections.map((item) => item.code),
      containsAll(<MemoryPatchErrorCode>{
        MemoryPatchErrorCode.lockedField,
        MemoryPatchErrorCode.unknownField,
        MemoryPatchErrorCode.noEffect,
      }),
    );
  });

  test('does not coerce an unknown action to set', () {
    final parsed = MemoryPatch.fromJson(<String, dynamic>{
      'section': 'user',
      'field': 'preferences',
      'action': 'invent',
      'value': 'concise',
    });

    expect(parsed.action, 'invent');
  });

  test('wrong patch value types are rejected without throwing', () async {
    final patch = MemoryPatch.fromJson(<String, dynamic>{
      'section': 'user',
      'field': 'preferences',
      'action': 'add',
      'value': 42,
    });

    final result = await service.applyMemoryPatches(<MemoryPatch>[patch]);

    expect(result.status, MemoryUpdateStatus.noEffect);
    expect(
      result.rejections.single.code,
      MemoryPatchErrorCode.invalidArguments,
    );
  });

  test(
    'system prompt links self-reference to mandatory memory tools',
    () async {
      final prompt = await service.buildSystemPrompt(
        memory: const UserMemory(),
      );

      expect(prompt, contains('currently speaking'));
      expect(prompt, contains('yourself'));
      expect(prompt, contains('from now on'));
      expect(prompt, contains('must call'));
      expect(prompt, contains('one-turn'));
      expect(prompt, contains('must not claim'));
    },
  );
}
