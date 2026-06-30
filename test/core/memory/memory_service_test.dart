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
}
