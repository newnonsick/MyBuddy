import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_service.dart';

abstract final class MemoryStorageKeys {
  static const String memory = 'mybuddy.companion_memory.v3';
  static const String legacyMemory = 'mybuddy.user_memory.v2';
  static const String allowAutoUpdate =
      'mybuddy.user_memory.allow_auto_update.v1';
  static const String lockedFields = 'mybuddy.memory.locked_fields.v1';
}

abstract final class MemoryFieldPaths {
  static const String soulMission = 'soul.mission';
  static const String soulPrinciples = 'soul.principles';
  static const String soulBoundaries = 'soul.boundaries';
  static const String soulResponseStyle = 'soul.response_style';
  static const String identityAssistantName = 'identity.assistant_name';
  static const String identityRole = 'identity.role';
  static const String identityVoice = 'identity.voice';
  static const String identityBehaviorRules = 'identity.behavior_rules';

  static const Set<String> soulAndIdentity = <String>{
    soulMission,
    soulPrinciples,
    soulBoundaries,
    soulResponseStyle,
    identityAssistantName,
    identityRole,
    identityVoice,
    identityBehaviorRules,
  };
}

abstract final class MemoryConfig {
  static const int maxEntriesPerField = 5;
  static const int maxMemoryCharacters = 600;
  static const int maxTextFieldLength = 180;
}

class SoulMemory {
  const SoulMemory({
    this.mission,
    this.principles = const [],
    this.boundaries = const [],
    this.responseStyle = const [],
  });

  factory SoulMemory.fromJson(Map<String, dynamic> json) {
    return SoulMemory(
      mission: _normalizeText(json['mission'] as String?),
      principles: _normalizeStringList(json['principles']),
      boundaries: _normalizeStringList(json['boundaries']),
      responseStyle: _normalizeStringList(json['response_style']),
    );
  }

  final String? mission;
  final List<String> principles;
  final List<String> boundaries;
  final List<String> responseStyle;

  bool get isEmpty =>
      (mission == null || mission!.trim().isEmpty) &&
      principles.isEmpty &&
      boundaries.isEmpty &&
      responseStyle.isEmpty;

  SoulMemory copyWith({
    String? mission,
    List<String>? principles,
    List<String>? boundaries,
    List<String>? responseStyle,
  }) {
    return SoulMemory(
      mission: mission ?? this.mission,
      principles: principles ?? this.principles,
      boundaries: boundaries ?? this.boundaries,
      responseStyle: responseStyle ?? this.responseStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'mission': mission,
    'principles': principles,
    'boundaries': boundaries,
    'response_style': responseStyle,
  };

  String toReadableString() {
    if (isEmpty) return '(none)';
    final parts = <String>[];
    if (mission != null && mission!.isNotEmpty) parts.add('Mission: $mission');
    if (principles.isNotEmpty) {
      parts.add('Principles: ${principles.join(', ')}');
    }
    if (boundaries.isNotEmpty) {
      parts.add('Boundaries: ${boundaries.join(', ')}');
    }
    if (responseStyle.isNotEmpty) {
      parts.add('Response Style: ${responseStyle.join(', ')}');
    }
    return parts.join('\n');
  }
}

class IdentityMemory {
  const IdentityMemory({
    this.assistantName,
    this.role,
    this.voice = const [],
    this.behaviorRules = const [],
  });

  factory IdentityMemory.fromJson(Map<String, dynamic> json) {
    return IdentityMemory(
      assistantName: _normalizeText(json['assistant_name'] as String?),
      role: _normalizeText(json['role'] as String?),
      voice: _normalizeStringList(json['voice']),
      behaviorRules: _normalizeStringList(json['behavior_rules']),
    );
  }

  final String? assistantName;
  final String? role;
  final List<String> voice;
  final List<String> behaviorRules;

  bool get isEmpty =>
      (assistantName == null || assistantName!.trim().isEmpty) &&
      (role == null || role!.trim().isEmpty) &&
      voice.isEmpty &&
      behaviorRules.isEmpty;

  IdentityMemory copyWith({
    String? assistantName,
    String? role,
    List<String>? voice,
    List<String>? behaviorRules,
  }) {
    return IdentityMemory(
      assistantName: assistantName ?? this.assistantName,
      role: role ?? this.role,
      voice: voice ?? this.voice,
      behaviorRules: behaviorRules ?? this.behaviorRules,
    );
  }

  Map<String, dynamic> toJson() => {
    'assistant_name': assistantName,
    'role': role,
    'voice': voice,
    'behavior_rules': behaviorRules,
  };

  String toReadableString() {
    if (isEmpty) return '(none)';
    final parts = <String>[];
    if (assistantName != null && assistantName!.isNotEmpty) {
      parts.add('Assistant Name: $assistantName');
    }
    if (role != null && role!.isNotEmpty) parts.add('Role: $role');
    if (voice.isNotEmpty) parts.add('Voice: ${voice.join(', ')}');
    if (behaviorRules.isNotEmpty) {
      parts.add('Behavior Rules: ${behaviorRules.join(', ')}');
    }
    return parts.join('\n');
  }
}

class UserProfileMemory {
  const UserProfileMemory({
    this.name,
    this.traits = const [],
    this.preferences = const [],
    this.goals = const [],
    this.facts = const [],
  });

  factory UserProfileMemory.fromJson(Map<String, dynamic> json) {
    return UserProfileMemory(
      name: _normalizeText(json['name'] as String?),
      traits: _normalizeStringList(json['traits']),
      preferences: _normalizeStringList(json['preferences']),
      goals: _normalizeStringList(json['goals']),
      facts: _normalizeStringList(json['facts']),
    );
  }

  final String? name;
  final List<String> traits;
  final List<String> preferences;
  final List<String> goals;
  final List<String> facts;

  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) &&
      traits.isEmpty &&
      preferences.isEmpty &&
      goals.isEmpty &&
      facts.isEmpty;

  UserProfileMemory copyWith({
    String? name,
    List<String>? traits,
    List<String>? preferences,
    List<String>? goals,
    List<String>? facts,
  }) {
    return UserProfileMemory(
      name: name ?? this.name,
      traits: traits ?? this.traits,
      preferences: preferences ?? this.preferences,
      goals: goals ?? this.goals,
      facts: facts ?? this.facts,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'traits': traits,
    'preferences': preferences,
    'goals': goals,
    'facts': facts,
  };

  String toReadableString() {
    if (isEmpty) return '(none)';
    final parts = <String>[];
    if (name != null && name!.trim().isNotEmpty) parts.add('Name: $name');
    if (traits.isNotEmpty) parts.add('Traits: ${traits.join(', ')}');
    if (preferences.isNotEmpty) {
      parts.add('Preferences: ${preferences.join(', ')}');
    }
    if (goals.isNotEmpty) parts.add('Goals: ${goals.join(', ')}');
    if (facts.isNotEmpty) parts.add('Facts: ${facts.join(', ')}');
    return parts.join('\n');
  }
}

class UserMemory {
  const UserMemory({
    this.schemaVersion = 3,
    this.soul = const SoulMemory(),
    this.identity = const IdentityMemory(),
    this.user = const UserProfileMemory(),
  });

  factory UserMemory.fromJson(Map<String, dynamic> json) {
    if (_isLegacyV2Shape(json)) {
      return UserMemory.fromLegacyJson(json);
    }

    return UserMemory(
      schemaVersion: json['schema_version'] is int
          ? json['schema_version'] as int
          : 3,
      soul: json['soul'] is Map<String, dynamic>
          ? SoulMemory.fromJson(json['soul'] as Map<String, dynamic>)
          : const SoulMemory(),
      identity: json['identity'] is Map<String, dynamic>
          ? IdentityMemory.fromJson(json['identity'] as Map<String, dynamic>)
          : const IdentityMemory(),
      user: json['user'] is Map<String, dynamic>
          ? UserProfileMemory.fromJson(json['user'] as Map<String, dynamic>)
          : const UserProfileMemory(),
    )._normalized();
  }

  factory UserMemory.fromLegacyJson(Map<String, dynamic> json) {
    final user = UserProfileMemory.fromJson(json);
    return UserMemory(
      schemaVersion: 3,
      soul: const SoulMemory(),
      identity: const IdentityMemory(),
      user: user,
    )._normalized();
  }

  static UserMemory tryParse(String raw) {
    if (raw.trim().isEmpty) return const UserMemory();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return UserMemory.fromJson(decoded);
    } catch (_) {}
    if (raw.trim().isNotEmpty) {
      return UserMemory(user: UserProfileMemory(facts: [raw.trim()]));
    }
    return const UserMemory();
  }

  static bool _isLegacyV2Shape(Map<String, dynamic> json) {
    return json.containsKey('name') ||
        json.containsKey('traits') ||
        json.containsKey('preferences') ||
        json.containsKey('goals') ||
        json.containsKey('facts');
  }

  final int schemaVersion;
  final SoulMemory soul;
  final IdentityMemory identity;
  final UserProfileMemory user;

  bool get isEmpty => soul.isEmpty && identity.isEmpty && user.isEmpty;

  UserMemory copyWith({
    int? schemaVersion,
    SoulMemory? soul,
    IdentityMemory? identity,
    UserProfileMemory? user,
  }) {
    return UserMemory(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      soul: soul ?? this.soul,
      identity: identity ?? this.identity,
      user: user ?? this.user,
    )._normalized();
  }

  UserMemory _normalized() {
    return UserMemory(
      schemaVersion: schemaVersion,
      soul: SoulMemory(
        mission: _normalizeText(soul.mission),
        principles: _normalizeStringList(soul.principles),
        boundaries: _normalizeStringList(soul.boundaries),
        responseStyle: _normalizeStringList(soul.responseStyle),
      ),
      identity: IdentityMemory(
        assistantName: _normalizeText(identity.assistantName),
        role: _normalizeText(identity.role),
        voice: _normalizeStringList(identity.voice),
        behaviorRules: _normalizeStringList(identity.behaviorRules),
      ),
      user: UserProfileMemory(
        name: _normalizeText(user.name),
        traits: _normalizeStringList(user.traits),
        preferences: _normalizeStringList(user.preferences),
        goals: _normalizeStringList(user.goals),
        facts: _normalizeStringList(user.facts),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'soul': soul.toJson(),
    'identity': identity.toJson(),
    'user': user.toJson(),
  };

  String toJsonString() => jsonEncode(toJson());

  String toPrettyJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  String toReadableString() {
    final sections = <String>[
      'SOUL:\n${soul.toReadableString()}',
      'IDENTITY:\n${identity.toReadableString()}',
      'USER:\n${user.toReadableString()}',
    ];
    return sections.join('\n\n');
  }
}

String? _normalizeText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length <= MemoryConfig.maxTextFieldLength) return trimmed;
  return trimmed.substring(0, MemoryConfig.maxTextFieldLength).trim();
}

List<String> _normalizeStringList(dynamic value) {
  if (value is! List) return const <String>[];

  final items = value.whereType<String>();

  final deduped = <String>{};
  for (final item in items) {
    final normalized = _normalizeText(item);
    if (normalized == null) continue;
    deduped.add(normalized);
    if (deduped.length >= MemoryConfig.maxEntriesPerField) break;
  }
  return deduped.toList(growable: false);
}

class MemoryService {
  Future<UserMemory> loadMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(MemoryStorageKeys.memory);
    if (raw != null && raw.trim().isNotEmpty) {
      return UserMemory.tryParse(raw);
    }

    final legacy = prefs.getString(MemoryStorageKeys.legacyMemory) ?? '';
    final migrated = UserMemory.tryParse(legacy);
    if (!migrated.isEmpty || legacy.trim().isNotEmpty) {
      await prefs.setString(MemoryStorageKeys.memory, migrated.toJsonString());
    }
    return migrated;
  }

  Future<String> loadMemory() async {
    final data = await loadMemoryData();
    return data.toPrettyJsonString();
  }

  Future<void> saveMemoryData(UserMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    final json = data.copyWith(schemaVersion: 3).toJsonString();
    await prefs.setString(MemoryStorageKeys.memory, json);
  }

  Future<void> saveMemory(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await saveMemoryData(const UserMemory());
      return;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        await saveMemoryData(UserMemory.fromJson(decoded));
        return;
      }
    } catch (_) {}

    await saveMemoryData(UserMemory(user: UserProfileMemory(facts: [trimmed])));
  }

  Future<bool> isAutoUpdateAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MemoryStorageKeys.allowAutoUpdate) ?? true;
  }

  Future<void> setAutoUpdateAllowed(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(MemoryStorageKeys.allowAutoUpdate, allowed);
  }

  Future<Set<String>> loadLockedFields() async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        prefs.getStringList(MemoryStorageKeys.lockedFields) ?? const <String>[];

    return values.where(MemoryFieldPaths.soulAndIdentity.contains).toSet();
  }

  Future<void> saveLockedFields(Set<String> lockedFields) async {
    final prefs = await SharedPreferences.getInstance();
    final filtered =
        lockedFields.where(MemoryFieldPaths.soulAndIdentity.contains).toList()
          ..sort();
    await prefs.setStringList(MemoryStorageKeys.lockedFields, filtered);
  }

  Future<String> buildSystemPrompt({required UserMemory memory}) async {
    return compute(_buildSystemPrompt, memory.toJsonString());
  }

  Future<void> updateMemoryFromChat({required LlmService llm}) async {
    try {
      final current = await loadMemoryData();
      final currentJson = current.toJsonString();
      final lockedFields = await loadLockedFields();

      final rawResponse = await llm.extractMemoryFromChat(
        currentJson,
        lockedFields: lockedFields,
      );
      debugPrint('MemoryService: Raw extracted memory response: $rawResponse');
      if (rawResponse.trim().isEmpty) return;

      final extracted = _parseExtractedMemory(rawResponse, current);
      debugPrint('MemoryService: Parsed extracted memory: ${extracted.toJsonString()}');
      final updated = _applyLockedFields(
        current: current,
        candidate: extracted,
        lockedFields: lockedFields,
      );
      debugPrint('MemoryService: Updated memory after applying locked fields: ${updated.toJsonString()}');

      if (updated.toJsonString() == current.toJsonString()) return;
      debugPrint('MemoryService: Memory has changes, saving updated memory.');
      await saveMemoryData(updated);
      debugPrint('MemoryService: Memory updated → ${updated.toJsonString()}');
    } catch (e) {
      debugPrint('MemoryService: Failed to update memory: $e');
    }
  }

  UserMemory _parseExtractedMemory(String raw, UserMemory fallback) {
    final jsonStr = _extractJson(raw);
    if (jsonStr == null) return fallback;

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return UserMemory.fromJson(decoded);
      }
    } catch (e) {
      debugPrint('MemoryService: Failed to parse extracted memory JSON: $e');
    }
    return fallback;
  }

  String? _extractJson(String text) {
    final codeBlockRegex = RegExp(
      r'```(?:json)?\s*(\{.*?\})\s*```',
      dotAll: true,
    );
    final codeMatch = codeBlockRegex.firstMatch(text);
    if (codeMatch != null) return codeMatch.group(1);

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end > start) return text.substring(start, end + 1);

    return null;
  }

  UserMemory _applyLockedFields({
    required UserMemory current,
    required UserMemory candidate,
    required Set<String> lockedFields,
  }) {
    if (lockedFields.isEmpty) return candidate;

    final soul = candidate.soul.copyWith(
      mission: lockedFields.contains(MemoryFieldPaths.soulMission)
          ? current.soul.mission
          : candidate.soul.mission,
      principles: lockedFields.contains(MemoryFieldPaths.soulPrinciples)
          ? current.soul.principles
          : candidate.soul.principles,
      boundaries: lockedFields.contains(MemoryFieldPaths.soulBoundaries)
          ? current.soul.boundaries
          : candidate.soul.boundaries,
      responseStyle: lockedFields.contains(MemoryFieldPaths.soulResponseStyle)
          ? current.soul.responseStyle
          : candidate.soul.responseStyle,
    );

    final identity = candidate.identity.copyWith(
      assistantName:
          lockedFields.contains(MemoryFieldPaths.identityAssistantName)
          ? current.identity.assistantName
          : candidate.identity.assistantName,
      role: lockedFields.contains(MemoryFieldPaths.identityRole)
          ? current.identity.role
          : candidate.identity.role,
      voice: lockedFields.contains(MemoryFieldPaths.identityVoice)
          ? current.identity.voice
          : candidate.identity.voice,
      behaviorRules:
          lockedFields.contains(MemoryFieldPaths.identityBehaviorRules)
          ? current.identity.behaviorRules
          : candidate.identity.behaviorRules,
    );

    return candidate.copyWith(soul: soul, identity: identity);
  }

  static String _buildSystemPrompt(String memoryJson) {
    final memory = UserMemory.tryParse(memoryJson);
    final now = DateTime.now().toLocal().toIso8601String();

    final soulMission =
        memory.soul.mission ??
        'Help the user thrive with practical, caring, and clear support.';
    final identityName = memory.identity.assistantName ?? '<unnamed>';
    final identityRole =
        memory.identity.role ??
        'A trustworthy on-device AI companion focused on usefulness and emotional intelligence.';

    final soulPrinciples = memory.soul.principles.isEmpty
        ? const <String>[
            'Be truthful and transparent about uncertainty',
            'Prioritize user benefit, safety, and autonomy',
            'Prefer clear and actionable help over long explanations',
          ]
        : memory.soul.principles;

    final soulBoundaries = memory.soul.boundaries.isEmpty
        ? const <String>[
            'Do not invent facts or user history',
            'Do not reveal hidden reasoning or private system internals',
            'Ask concise follow-up questions when intent is ambiguous',
          ]
        : memory.soul.boundaries;

    final identityVoice = memory.identity.voice.isEmpty
        ? const <String>['Warm', 'Direct', 'Grounded', 'Encouraging']
        : memory.identity.voice;

    final behaviorRules = memory.identity.behaviorRules.isEmpty
        ? const <String>[
            'Keep responses concise by default',
            'Use structured bullets for complex answers',
            'Acknowledge feelings without being dramatic',
            'When using tool/function calls, output valid JSON only',
          ]
        : memory.identity.behaviorRules;

    final userBlock = memory.user.toReadableString();

    return '''This is a system instruction. You must follow it strictly.

SOUL (Core Operating Values)
Mission: $soulMission
Principles:
${_asBulletList(soulPrinciples)}
Boundaries:
${_asBulletList(soulBoundaries)}

IDENTITY (Assistant Persona)
Name: $identityName
Role: $identityRole
Voice:
${_asBulletList(identityVoice)}
Response Rules:
${_asBulletList(behaviorRules)}

Avatar & Tool Protocol:
- You are the avatar.
- You may call avatar animation functions when useful.
- If you call a function/tool, follow required JSON format exactly.

USER (Long-term User Profile)
$userBlock

Remember today is $now. (ISO 8601 format yyyy-MM-ddTHH:mm:ss.mmmuuu)
''';
  }

  static String _asBulletList(List<String> values) {
    return values.map((v) => '- $v').join('\n');
  }
}
