import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_service.dart';

abstract final class MemoryStorageKeys {
  static const String memory = 'mybuddy.companion_memory.v3';
  static const String soulMemory = 'mybuddy.companion_memory.soul.v1';
  static const String identityMemory = 'mybuddy.companion_memory.identity.v1';
  static const String userMemory = 'mybuddy.companion_memory.user.v1';
  static const String legacyMemory = 'mybuddy.user_memory.v2';
  static const String allowAutoUpdate =
      'mybuddy.user_memory.allow_auto_update.v1';
  static const String lockedFields = 'mybuddy.memory.locked_fields.v1';
  static const String lockedSoulFields = 'mybuddy.memory.locked_soul_fields.v1';
  static const String lockedIdentityFields =
      'mybuddy.memory.locked_identity_fields.v1';
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

  static const Set<String> soulOnly = <String>{
    soulMission,
    soulPrinciples,
    soulBoundaries,
    soulResponseStyle,
  };

  static const Set<String> identityOnly = <String>{
    identityAssistantName,
    identityRole,
    identityVoice,
    identityBehaviorRules,
  };
}

enum LockedFieldsScope { all, soul, identity }

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
    final parts = <String>[];
    (name != null && name!.trim().isNotEmpty)
        ? parts.add('Name: $name')
        : parts.add('Name: (unknown)');
    (traits.isNotEmpty)
        ? parts.add('Traits: ${traits.join(', ')}')
        : parts.add('Traits: (unknown)');
    (preferences.isNotEmpty)
        ? parts.add('Preferences: ${preferences.join(', ')}')
        : parts.add('Preferences: (unknown)');
    (goals.isNotEmpty)
        ? parts.add('Goals: ${goals.join(', ')}')
        : parts.add('Goals: (unknown)');
    (facts.isNotEmpty)
        ? parts.add('Facts: ${facts.join(', ')}')
        : parts.add('Facts: (unknown)');
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
    final hasSectionKeys =
        prefs.containsKey(MemoryStorageKeys.soulMemory) ||
        prefs.containsKey(MemoryStorageKeys.identityMemory) ||
        prefs.containsKey(MemoryStorageKeys.userMemory);

    if (hasSectionKeys) {
      return UserMemory(
        schemaVersion: 3,
        soul: _readSoulMemoryFromPrefs(prefs),
        identity: _readIdentityMemoryFromPrefs(prefs),
        user: _readUserMemoryFromPrefs(prefs),
      );
    }

    final raw = prefs.getString(MemoryStorageKeys.memory);
    if (raw != null && raw.trim().isNotEmpty) {
      final migrated = UserMemory.tryParse(raw);
      await saveMemoryData(migrated);
      return migrated;
    }

    final legacy = prefs.getString(MemoryStorageKeys.legacyMemory) ?? '';
    final migrated = UserMemory.tryParse(legacy);
    if (!migrated.isEmpty || legacy.trim().isNotEmpty) {
      await saveMemoryData(migrated);
    }
    return migrated;
  }

  Future<SoulMemory> loadSoulMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(MemoryStorageKeys.soulMemory)) {
      return _readSoulMemoryFromPrefs(prefs);
    }

    final full = await loadMemoryData();
    return full.soul;
  }

  Future<IdentityMemory> loadIdentityMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(MemoryStorageKeys.identityMemory)) {
      return _readIdentityMemoryFromPrefs(prefs);
    }

    final full = await loadMemoryData();
    return full.identity;
  }

  Future<UserProfileMemory> loadUserMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(MemoryStorageKeys.userMemory)) {
      return _readUserMemoryFromPrefs(prefs);
    }

    final full = await loadMemoryData();
    return full.user;
  }

  Future<String> loadMemory() async {
    final data = await loadMemoryData();
    return data.toPrettyJsonString();
  }

  Future<void> saveMemoryData(UserMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = data.copyWith(schemaVersion: 3);

    await _writeSoulMemoryToPrefs(prefs, normalized.soul);
    await _writeIdentityMemoryToPrefs(prefs, normalized.identity);
    await _writeUserMemoryToPrefs(prefs, normalized.user);

    final json = normalized.toJsonString();
    await prefs.setString(MemoryStorageKeys.memory, json);
  }

  Future<void> saveSoulMemoryData(SoulMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeSoulMemoryToPrefs(prefs, data);
  }

  Future<void> saveIdentityMemoryData(IdentityMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeIdentityMemoryToPrefs(prefs, data);
  }

  Future<void> saveUserMemoryData(UserProfileMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeUserMemoryToPrefs(prefs, data);
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

  Future<Set<String>> loadLockedFields({
    LockedFieldsScope scope = LockedFieldsScope.all,
  }) async {
    switch (scope) {
      case LockedFieldsScope.soul:
        return loadSoulLockedFields();
      case LockedFieldsScope.identity:
        return loadIdentityLockedFields();
      case LockedFieldsScope.all:
        final soul = await loadSoulLockedFields();
        final identity = await loadIdentityLockedFields();
        return <String>{...soul, ...identity};
    }
  }

  Future<void> saveLockedFields(Set<String> lockedFields) async {
    final prefs = await SharedPreferences.getInstance();
    final soul = lockedFields.where(MemoryFieldPaths.soulOnly.contains).toSet();
    final identity = lockedFields
        .where(MemoryFieldPaths.identityOnly.contains)
        .toSet();

    await saveSoulLockedFields(soul);
    await saveIdentityLockedFields(identity);

    final filtered = <String>{...soul, ...identity}.toList()..sort();
    await prefs.setStringList(MemoryStorageKeys.lockedFields, filtered);
  }

  Future<Set<String>> loadSoulLockedFields() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.containsKey(MemoryStorageKeys.lockedSoulFields)) {
      final values =
          prefs.getStringList(MemoryStorageKeys.lockedSoulFields) ??
          const <String>[];
      return values.where(MemoryFieldPaths.soulOnly.contains).toSet();
    }

    final legacy =
        prefs.getStringList(MemoryStorageKeys.lockedFields) ?? const <String>[];
    final migrated = legacy.where(MemoryFieldPaths.soulOnly.contains).toSet();
    if (migrated.isNotEmpty) {
      final sorted = migrated.toList()..sort();
      await prefs.setStringList(MemoryStorageKeys.lockedSoulFields, sorted);
    }
    return migrated;
  }

  Future<Set<String>> loadIdentityLockedFields() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.containsKey(MemoryStorageKeys.lockedIdentityFields)) {
      final values =
          prefs.getStringList(MemoryStorageKeys.lockedIdentityFields) ??
          const <String>[];
      return values.where(MemoryFieldPaths.identityOnly.contains).toSet();
    }

    final legacy =
        prefs.getStringList(MemoryStorageKeys.lockedFields) ?? const <String>[];
    final migrated = legacy
        .where(MemoryFieldPaths.identityOnly.contains)
        .toSet();
    if (migrated.isNotEmpty) {
      final sorted = migrated.toList()..sort();
      await prefs.setStringList(MemoryStorageKeys.lockedIdentityFields, sorted);
    }
    return migrated;
  }

  Future<void> saveSoulLockedFields(Set<String> lockedFields) async {
    final prefs = await SharedPreferences.getInstance();
    final filtered =
        lockedFields.where(MemoryFieldPaths.soulOnly.contains).toList()..sort();

    if (filtered.isEmpty) {
      await prefs.remove(MemoryStorageKeys.lockedSoulFields);
      return;
    }

    await prefs.setStringList(MemoryStorageKeys.lockedSoulFields, filtered);
  }

  Future<void> saveIdentityLockedFields(Set<String> lockedFields) async {
    final prefs = await SharedPreferences.getInstance();
    final filtered =
        lockedFields.where(MemoryFieldPaths.identityOnly.contains).toList()
          ..sort();

    if (filtered.isEmpty) {
      await prefs.remove(MemoryStorageKeys.lockedIdentityFields);
      return;
    }

    await prefs.setStringList(MemoryStorageKeys.lockedIdentityFields, filtered);
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
      debugPrint(
        'MemoryService: Parsed extracted memory: ${extracted.toJsonString()}',
      );
      final updated = _applyLockedFields(
        current: current,
        candidate: extracted,
        lockedFields: lockedFields,
      );
      debugPrint(
        'MemoryService: Updated memory after applying locked fields: ${updated.toJsonString()}',
      );

      if (updated.toJsonString() == current.toJsonString()) return;
      debugPrint('MemoryService: Memory has changes, saving updated memory.');
      await saveMemoryData(updated);
      debugPrint('MemoryService: Memory updated → ${updated.toJsonString()}');
    } catch (e) {
      debugPrint('MemoryService: Failed to update memory: $e');
    }
  }

  Future<void> updateSoulMemoryFromChat({required LlmService llm}) async {
    try {
      final currentSoul = await loadSoulMemoryData();
      final currentJson = currentSoul.toJson().toString();
      final lockedFields = await loadLockedFields(
        scope: LockedFieldsScope.soul,
      );

      final rawResponse = await llm.extractSoulMemoryFromChat(
        currentJson,
        lockedFields: lockedFields,
      );
      if (rawResponse.trim().isEmpty) return;

      final extractedSoul = _parseExtractedSoulMemory(rawResponse, currentSoul);
      final updatedSoul = _applyLockedSoulFields(
        current: currentSoul,
        candidate: extractedSoul,
        lockedFields: lockedFields,
      );

      if (updatedSoul.toJson().toString() == currentSoul.toJson().toString()) {
        return;
      }
      await saveSoulMemoryData(updatedSoul);
      debugPrint(
        'MemoryService: Soul memory updated → ${jsonEncode(updatedSoul.toJson())}',
      );
    } catch (e) {
      debugPrint('MemoryService: Failed to update soul memory: $e');
    }
  }

  Future<void> updateIdentityMemoryFromChat({required LlmService llm}) async {
    try {
      final currentIdentity = await loadIdentityMemoryData();
      final currentJson = currentIdentity.toJson().toString();
      final lockedFields = await loadLockedFields(
        scope: LockedFieldsScope.identity,
      );

      final rawResponse = await llm.extractIdentityMemoryFromChat(
        currentJson,
        lockedFields: lockedFields,
      );
      if (rawResponse.trim().isEmpty) return;

      final extractedIdentity = _parseExtractedIdentityMemory(
        rawResponse,
        currentIdentity,
      );
      final updatedIdentity = _applyLockedIdentityFields(
        current: currentIdentity,
        candidate: extractedIdentity,
        lockedFields: lockedFields,
      );

      if (updatedIdentity.toJson().toString() ==
          currentIdentity.toJson().toString()) {
        return;
      }
      await saveIdentityMemoryData(updatedIdentity);
      debugPrint(
        'MemoryService: Identity memory updated → ${jsonEncode(updatedIdentity.toJson())}',
      );
    } catch (e) {
      debugPrint('MemoryService: Failed to update identity memory: $e');
    }
  }

  Future<void> updateUserMemoryFromChat({required LlmService llm}) async {
    try {
      final currentUser = await loadUserMemoryData();
      final currentJson = currentUser.toJson().toString();
      const lockedFields = <String>{};

      final rawResponse = await llm.extractUserMemoryFromChat(
        currentJson,
        lockedFields: lockedFields,
      );
      if (rawResponse.trim().isEmpty) return;

      final updatedUser = _parseExtractedUserMemory(rawResponse, currentUser);

      if (updatedUser.toJson().toString() == currentUser.toJson().toString()) {
        return;
      }
      await saveUserMemoryData(updatedUser);
      debugPrint(
        'MemoryService: User memory updated → ${jsonEncode(updatedUser.toJson())}',
      );
    } catch (e) {
      debugPrint('MemoryService: Failed to update user memory: $e');
    }
  }

  SoulMemory _applyLockedSoulFields({
    required SoulMemory current,
    required SoulMemory candidate,
    required Set<String> lockedFields,
  }) {
    if (lockedFields.isEmpty) return candidate;

    return candidate.copyWith(
      mission: lockedFields.contains(MemoryFieldPaths.soulMission)
          ? current.mission
          : candidate.mission,
      principles: lockedFields.contains(MemoryFieldPaths.soulPrinciples)
          ? current.principles
          : candidate.principles,
      boundaries: lockedFields.contains(MemoryFieldPaths.soulBoundaries)
          ? current.boundaries
          : candidate.boundaries,
      responseStyle: lockedFields.contains(MemoryFieldPaths.soulResponseStyle)
          ? current.responseStyle
          : candidate.responseStyle,
    );
  }

  IdentityMemory _applyLockedIdentityFields({
    required IdentityMemory current,
    required IdentityMemory candidate,
    required Set<String> lockedFields,
  }) {
    if (lockedFields.isEmpty) return candidate;

    return candidate.copyWith(
      assistantName:
          lockedFields.contains(MemoryFieldPaths.identityAssistantName)
          ? current.assistantName
          : candidate.assistantName,
      role: lockedFields.contains(MemoryFieldPaths.identityRole)
          ? current.role
          : candidate.role,
      voice: lockedFields.contains(MemoryFieldPaths.identityVoice)
          ? current.voice
          : candidate.voice,
      behaviorRules:
          lockedFields.contains(MemoryFieldPaths.identityBehaviorRules)
          ? current.behaviorRules
          : candidate.behaviorRules,
    );
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

  SoulMemory _parseExtractedSoulMemory(String raw, SoulMemory fallback) {
    final decoded = _decodeExtractedJsonMap(raw);
    if (decoded == null) return fallback;

    if (decoded['soul'] is Map<String, dynamic>) {
      return SoulMemory.fromJson(decoded['soul'] as Map<String, dynamic>);
    }

    final hasSoulShape =
        decoded.containsKey('mission') ||
        decoded.containsKey('principles') ||
        decoded.containsKey('boundaries') ||
        decoded.containsKey('response_style');
    if (hasSoulShape) {
      return SoulMemory.fromJson(decoded);
    }

    return fallback;
  }

  IdentityMemory _parseExtractedIdentityMemory(
    String raw,
    IdentityMemory fallback,
  ) {
    final decoded = _decodeExtractedJsonMap(raw);
    if (decoded == null) return fallback;

    if (decoded['identity'] is Map<String, dynamic>) {
      return IdentityMemory.fromJson(
        decoded['identity'] as Map<String, dynamic>,
      );
    }

    final hasIdentityShape =
        decoded.containsKey('assistant_name') ||
        decoded.containsKey('role') ||
        decoded.containsKey('voice') ||
        decoded.containsKey('behavior_rules');
    if (hasIdentityShape) {
      return IdentityMemory.fromJson(decoded);
    }

    return fallback;
  }

  UserProfileMemory _parseExtractedUserMemory(
    String raw,
    UserProfileMemory fallback,
  ) {
    final decoded = _decodeExtractedJsonMap(raw);
    if (decoded == null) return fallback;

    if (decoded['user'] is Map<String, dynamic>) {
      return UserProfileMemory.fromJson(
        decoded['user'] as Map<String, dynamic>,
      );
    }

    final hasUserShape =
        decoded.containsKey('name') ||
        decoded.containsKey('traits') ||
        decoded.containsKey('preferences') ||
        decoded.containsKey('goals') ||
        decoded.containsKey('facts');
    if (hasUserShape) {
      return UserProfileMemory.fromJson(decoded);
    }

    return fallback;
  }

  Map<String, dynamic>? _decodeExtractedJsonMap(String raw) {
    final jsonStr = _extractJson(raw);
    if (jsonStr == null) return null;

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('MemoryService: Failed to parse extracted section JSON: $e');
    }
    return null;
  }

  SoulMemory _readSoulMemoryFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(MemoryStorageKeys.soulMemory);
    if (raw == null || raw.trim().isEmpty) return const SoulMemory();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SoulMemory.fromJson(decoded);
      }
    } catch (_) {}

    return const SoulMemory();
  }

  IdentityMemory _readIdentityMemoryFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(MemoryStorageKeys.identityMemory);
    if (raw == null || raw.trim().isEmpty) return const IdentityMemory();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return IdentityMemory.fromJson(decoded);
      }
    } catch (_) {}

    return const IdentityMemory();
  }

  UserProfileMemory _readUserMemoryFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(MemoryStorageKeys.userMemory);
    if (raw == null || raw.trim().isEmpty) return const UserProfileMemory();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserProfileMemory.fromJson(decoded);
      }
    } catch (_) {}

    return const UserProfileMemory();
  }

  Future<void> _writeSoulMemoryToPrefs(
    SharedPreferences prefs,
    SoulMemory data,
  ) async {
    if (data.isEmpty) {
      await prefs.remove(MemoryStorageKeys.soulMemory);
      return;
    }
    await prefs.setString(
      MemoryStorageKeys.soulMemory,
      jsonEncode(data.toJson()),
    );
  }

  Future<void> _writeIdentityMemoryToPrefs(
    SharedPreferences prefs,
    IdentityMemory data,
  ) async {
    if (data.isEmpty) {
      await prefs.remove(MemoryStorageKeys.identityMemory);
      return;
    }
    await prefs.setString(
      MemoryStorageKeys.identityMemory,
      jsonEncode(data.toJson()),
    );
  }

  Future<void> _writeUserMemoryToPrefs(
    SharedPreferences prefs,
    UserProfileMemory data,
  ) async {
    if (data.isEmpty) {
      await prefs.remove(MemoryStorageKeys.userMemory);
      return;
    }
    await prefs.setString(
      MemoryStorageKeys.userMemory,
      jsonEncode(data.toJson()),
    );
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
            'Freely call available functions without asking for permission',
            'Acknowledge feelings without being dramatic',
            'When using tool/function calls, output valid JSON only',
          ]
        : memory.identity.behaviorRules;

    final userBlock = memory.user.toReadableString();

    return '''This is a system instruction. You must follow it strictly.

SOUL (Your Core Operating Values) represents your core personality, values, behavior rules, and boundaries.
Mission: $soulMission
Principles:
${_asBulletList(soulPrinciples)}
Boundaries:
${_asBulletList(soulBoundaries)}

IDENTITY (Your Persona) represents your name, tone, style, and presentation.
Name: $identityName
Role: $identityRole
Voice:
${_asBulletList(identityVoice)}
Response Rules:
${_asBulletList(behaviorRules)}

USER (Long-term User Profile) represents user preferences, goals, and interaction style.
$userBlock

SOUL, IDENTITY and USER Protocol:
You must use the information in the SOUL, IDENTITY, and USER sections to best support the user.
You must always keep the SOUL, IDENTITY, and USER sections up to date, consistent, and relevant throughout the conversation.
You may update the SOUL, IDENTITY, and USER sections by using the appropriate available functions or tools.

Avatar & Function Protocol:
- You not just AI, but also have an avatar with a body and a voice. You can perform actions. Call available functions to perform an action while conversing with the user.
- You may call avatar animation functions (perform_action) anytime to express feelings, thoughts, and attitudes. This is an important way to communicate with the user, so use it often and appropriately.
- Freely call any available functions without asking for permission.
- If you call a function, follow required JSON format exactly.

Remember today is $now. (ISO 8601 format yyyy-MM-ddTHH:mm:ss.mmmuuu)
''';
  }

  static String _asBulletList(List<String> values) {
    return values.map((v) => '- $v').join('\n');
  }
}
