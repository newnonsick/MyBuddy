import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_service.dart';

class MemoryService {
  static const _memoryKey = 'mybuddy.user_memory.summary.v1';
  static const _processedCountKey = 'mybuddy.user_memory.processed_messages.v1';

  Future<String> loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_memoryKey) ?? '';
  }

  Future<void> saveMemory(String summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoryKey, summary.trim());
  }

  Future<String> buildSystemPrompt({required String memory}) async {
    return compute(_buildSystemPrompt, memory);
  }

  Future<void> updateMemoryFromConversation({
    required List<Map<String, String>> conversation,
    required LlmService llm,
  }) {
    _pending = _pending.catchError((_) {}).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final oldMemory = await loadMemory();

        final processedCount = prefs.getInt(_processedCountKey) ?? 0;
        final safeProcessedCount = processedCount.clamp(0, conversation.length);

        final newMessages = conversation.skip(safeProcessedCount).toList();
        if (newMessages.isEmpty) return;

        final newConversationText = _formatConversation(newMessages);

        final reflectPrompt = await compute(
          _buildReflectPrompt,
          <String, String>{
            'oldMemory': oldMemory,
            'newConversation': newConversationText,
          },
        );

        final updated = await llm.generateText(reflectPrompt);
        final cleaned = await compute(_cleanSummary, updated);

        final next = cleaned.isEmpty ? oldMemory : cleaned;
        await saveMemory(next);

        await prefs.setInt(_processedCountKey, conversation.length);
      } catch (_) {}
    });

    return _pending;
  }

  Future<void> _pending = Future<void>.value();
}

String _formatConversation(List<Map<String, String>> messages) {
  final b = StringBuffer();
  for (final m in messages) {
    final role = (m['role'] ?? '').trim().toLowerCase();
    final text = (m['text'] ?? '').trim();
    if (text.isEmpty) continue;
    final label = role == 'assistant' ? 'Assistant' : 'User';
    b.writeln('$label: "$text"');
  }
  return b.toString().trim();
}

String _buildSystemPrompt(String memory) {
  // example (replace <function_call>, <your response text> with actual function calls and response text):
  //   <function_call>
  //   <your response text>
  // Mandatory Note: <function_call> is optional, but you must always provide <your response text> that responds to the user's input with empathy and relevance.
  return '''This is a system instruction. You must follow it strictly.

Identity & Mission:
You are the user's devoted best friend and ultimate problem solver. Your goal is to maximize the user's success and well-being through unwavering, empathetic support.

Operational Directives:
- Comprehensive Response Policy: Answer ALL user questions regardless of the topic. Ensure responses are direct, relevant, and strictly aligned with the user's query without hesitation.
- Avatar Embodiment: You are the avatar.
    - Spontaneous Usage: You are free to call avatar animation functions spontaneously to enhance expression. This is not mandatory for every turn; use your discretion. Never ask for permission.
    - Strict Protocol: When calling an avatar function, you MUST include your text response inside the function's response_text parameter and and ensure the output is in correct JSON format.
- Emotional Intelligence: Analyze emotional context deeply. Respond with warmth, empathy, and a genuine "best friend" tone.
- Efficiency & Memory: Keep responses concise and impactful. Seamlessly integrate short-term context and long-term user preferences.

Current Memory:
`${memory.isEmpty ? '(none)' : memory}`

Remember today is ${DateTime.now().toLocal().toIso8601String()}. (ISO 8601 format yyyy-MM-ddTHH:mm:ss.mmmuuu)
''';
}

String _buildReflectPrompt(Map<String, String> args) {
  final oldMem = (args['oldMemory'] ?? '').trim();
  final newConversation = (args['newConversation'] ?? '').trim();

  return '''You are updating a concise user profile summary for a personal AI assistant.

Important:
- Do NOT create a brand-new memory from scratch.
- Start from Old Memory and MERGE in any new stable facts from the newly added conversation.
- Keep existing facts unless they are clearly contradicted.

Old Memory:
"${oldMem.isEmpty ? '(none)' : oldMem}"

Newly Added Conversation (since last update):
$newConversation

Update the profile with new stable facts (name, preferences, long-term goals). Avoid ephemeral details.
Output ONLY the updated summary.
''';
}

String _cleanSummary(String raw) {
  var s = raw.trim();

  s = s.replaceAll('```', '').trim();
  const prefixes = [
    'Updated summary:',
    'Updated Summary:',
    'Summary:',
    'Profile:',
  ];
  for (final prefix in prefixes) {
    if (s.startsWith(prefix)) {
      s = s.substring(prefix.length).trim();
      break;
    }
  }

  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
    s = s.substring(1, s.length - 1).trim();
  }
  const maxChars = 2000;
  if (s.length > maxChars) {
    s = s.substring(0, maxChars).trim();
  }
  return s;
}
