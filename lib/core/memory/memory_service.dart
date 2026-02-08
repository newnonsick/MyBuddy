import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_service.dart';

abstract final class MemoryStorageKeys {
  static const String memory = 'mybuddy.user_memory.summary.v1';
  static const String processedCount =
      'mybuddy.user_memory.processed_messages.v1';
  static const String allowAutoUpdate =
      'mybuddy.user_memory.allow_auto_update.v1';
}

abstract final class MemoryConfig {
  static const int maxMemoryCharacters = 200;
}

class MemoryService {
  Future<String> loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(MemoryStorageKeys.memory) ?? '';
  }

  Future<void> saveMemory(String summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(MemoryStorageKeys.memory, summary.trim());
  }

  Future<bool> isAutoUpdateAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MemoryStorageKeys.allowAutoUpdate) ?? true;
  }

  Future<void> setAutoUpdateAllowed(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(MemoryStorageKeys.allowAutoUpdate, allowed);
  }

  Future<String> buildSystemPrompt({required String memory}) async {
    return compute(_buildSystemPrompt, memory);
  }

  Future<void> updateMemoryFromConversation({
    required List<Map<String, String>> conversation,
    required LlmService llm,
  }) {
    _pending = _pending.catchError((_) {}).then((_) async {
      await _processMemoryUpdate(conversation, llm);
    });

    return _pending;
  }

  Future<void> _pending = Future<void>.value();

  Future<void> _processMemoryUpdate(
    List<Map<String, String>> conversation,
    LlmService llm,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldMemory = await loadMemory();

      final processedCount =
          prefs.getInt(MemoryStorageKeys.processedCount) ?? 0;
      final safeProcessedCount = processedCount.clamp(0, conversation.length);

      final newMessages = conversation.skip(safeProcessedCount).toList();
      if (newMessages.isEmpty) return;

      final newConversationText = _formatConversation(newMessages);

      final reflectPrompt = await compute(_buildReflectPrompt, <String, String>{
        'oldMemory': oldMemory,
        'newConversation': newConversationText,
      });

      final updated = await llm.generateText(reflectPrompt);
      final cleaned = await compute(_cleanSummary, updated);

      final next = cleaned.isEmpty ? oldMemory : cleaned;
      await saveMemory(next);
    } catch (e) {
      debugPrint('MemoryService: Failed to update memory: $e');
    }
  }
}

String _formatConversation(List<Map<String, String>> messages) {
  final buffer = StringBuffer();

  for (final message in messages) {
    final role = (message['role'] ?? '').trim().toLowerCase();
    final text = (message['text'] ?? '').trim();
    if (text.isEmpty) continue;

    final label = role == 'assistant' ? 'Assistant' : 'User';
    buffer.writeln('$label: "$text"');
  }

  return buffer.toString().trim();
}

String _buildSystemPrompt(String memory) {
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
`${memory.isEmpty ? '(none)' : memory}`

Remember today is $now. (ISO 8601 format yyyy-MM-ddTHH:mm:ss.mmmuuu)
''';
}

String _buildReflectPrompt(Map<String, String> args) {
  final oldMem = (args['oldMemory'] ?? '').trim();
  final newConversation = (args['newConversation'] ?? '').trim();

  return '''You are updating a concise user profile summary for a personal AI assistant.

Important:
- Start from Old Memory and MERGE in any new stable facts from the newly added conversation.
- Keep existing facts unless they are clearly contradicted.
- You are able to create a brand-new memory from scratch.

Old Memory:
"${oldMem.isEmpty ? '(none)' : oldMem}"

Newly Added Conversation (since last update):
$newConversation

Update the profile with new stable facts (name, preferences, long-term goals). Avoid ephemeral details.
Output ONLY the updated summary.
''';
}

String _cleanSummary(String raw) {
  var summary = raw.trim();

  summary = summary.replaceAll('```', '').trim();

  const prefixes = [
    'Updated summary:',
    'Updated Summary:',
    'Summary:',
    'Profile:',
  ];

  for (final prefix in prefixes) {
    if (summary.startsWith(prefix)) {
      summary = summary.substring(prefix.length).trim();
      break;
    }
  }

  if (summary.startsWith('"') && summary.endsWith('"') && summary.length >= 2) {
    summary = summary.substring(1, summary.length - 1).trim();
  }

  if (summary.length > MemoryConfig.maxMemoryCharacters) {
    summary = summary.substring(0, MemoryConfig.maxMemoryCharacters).trim();
  }

  return summary;
}
