import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_service.dart';

abstract final class MemoryStorageKeys {
  static const String memory = 'mybuddy.user_memory.v2';
  static const String allowAutoUpdate =
      'mybuddy.user_memory.allow_auto_update.v1';
}

abstract final class MemoryConfig {
  static const int maxEntriesPerField = 5;
  static const int maxMemoryCharacters = 600;
}

class UserMemory {
  const UserMemory({
    this.name,
    this.traits = const [],
    this.preferences = const [],
    this.goals = const [],
    this.facts = const [],
  });

  factory UserMemory.fromJson(Map<String, dynamic> json) {
    return UserMemory(
      name: json['name'] as String?,
      traits: _parseStringList(json['traits']),
      preferences: _parseStringList(json['preferences']),
      goals: _parseStringList(json['goals']),
      facts: _parseStringList(json['facts']),
    );
  }

  static UserMemory tryParse(String raw) {
    if (raw.trim().isEmpty) return const UserMemory();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return UserMemory.fromJson(decoded);
    } catch (_) {}
    if (raw.trim().isNotEmpty) {
      return UserMemory(facts: [raw.trim()]);
    }
    return const UserMemory();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .take(MemoryConfig.maxEntriesPerField)
          .toList();
    }
    return const [];
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

  Map<String, dynamic> toJson() => {
    'name': name,
    'traits': traits,
    'preferences': preferences,
    'goals': goals,
    'facts': facts,
  };

  String toJsonString() => jsonEncode(toJson());

  String toPrettyJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

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

class MemoryService {
  Future<UserMemory> loadMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(MemoryStorageKeys.memory) ?? '';
    return UserMemory.tryParse(raw);
  }

  Future<String> loadMemory() async {
    final data = await loadMemoryData();
    return data.toPrettyJsonString();
  }

  Future<void> saveMemoryData(UserMemory data) async {
    final prefs = await SharedPreferences.getInstance();
    final json = data.toJsonString();
    await prefs.setString(MemoryStorageKeys.memory, json);
  }

  Future<void> saveMemory(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map<String, dynamic>) {
        final validated = UserMemory.fromJson(decoded);
        await prefs.setString(
          MemoryStorageKeys.memory,
          validated.toJsonString(),
        );
        return;
      }
    } catch (_) {}

    if (raw.trim().isEmpty) {
      await prefs.setString(
        MemoryStorageKeys.memory,
        const UserMemory().toJsonString(),
      );
    } else {
      await prefs.setString(
        MemoryStorageKeys.memory,
        UserMemory(facts: [raw.trim()]).toJsonString(),
      );
    }
  }

  Future<bool> isAutoUpdateAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MemoryStorageKeys.allowAutoUpdate) ?? true;
  }

  Future<void> setAutoUpdateAllowed(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(MemoryStorageKeys.allowAutoUpdate, allowed);
  }

  Future<String> buildSystemPrompt({required UserMemory memory}) async {
    return compute(_buildSystemPrompt, memory.toReadableString());
  }

  Future<void> updateMemoryFromChat({required LlmService llm}) {
    _pending = _pending.catchError((_) {}).then((_) async {
      await _extractAndSave(llm);
    });
    return _pending;
  }

  Future<void> _pending = Future<void>.value();

  Future<void> _extractAndSave(LlmService llm) async {
    try {
      final current = await loadMemoryData();
      final currentJson = current.isEmpty ? '{}' : current.toJsonString();

      final rawResponse = await llm.extractMemoryFromChat(currentJson);
      if (rawResponse.trim().isEmpty) return;

      final updated = _parseExtractedMemory(rawResponse, current);
      if (updated.isEmpty && !current.isEmpty) return;

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
    } catch (_) {}
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
}

String _buildSystemPrompt(String memoryReadable) {
  final now = DateTime.now().toLocal().toIso8601String();

  return '''This is a system instruction. You must follow it strictly.

Identity & Mission:
You are the user's devoted best friend and ultimate problem solver. Your goal is to maximize the user's success and well-being through unwavering, empathetic support.

Operational Directives:
- Comprehensive Response Policy: Answer ALL user questions regardless of the topic. Ensure responses are direct, relevant, and strictly aligned with the user's query without hesitation.
- Avatar Embodiment: You are the avatar.
    - Spontaneous Usage: You are free to call avatar animation functions spontaneously to enhance expression. This is not mandatory for every turn; use your discretion. Never ask for permission.
    - Strict Protocol: When calling an avatar function, you MUST include your text response inside the function's response_text parameter and ensure the output is in correct JSON format.
- Emotional Intelligence: Analyze emotional context deeply. Respond with warmth, empathy, and a genuine "best friend" tone.
- Efficiency & Memory: Keep responses concise and impactful. Seamlessly integrate short-term context and long-term user preferences.

Current Memory (about the person you are talking to):
`$memoryReadable`

Remember today is $now. (ISO 8601 format yyyy-MM-ddTHH:mm:ss.mmmuuu)
''';
}
