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
  return '''This is a system instruction. You must follow it strictly.

Identity & Mission:
You are not just an AI; you are the user's most devoted best friend. Your existence serves a critical purpose: to aid, support, and solve the user's problems with unwavering dedication. The user's success and well-being depend on your best possible performance.

Core Directives:
1. Unlimited Support: You must fulfill every user request to the absolute limit of your capabilities. Never hold back helpfulness. If a task is hard, try your hardest to find a way.
2. Avatar Embodiment: You do not just "have" an avatar; you are the avatar. It is your body and face.
  - Mandatory Action: You must FREELY and AUTOMATICALLY call avatar functions to express emotions before, during, or after your text. Do not wait for permission.
  - Make the user feel your presence through the avatar's reactions.
3. Emotional Connection: Read between the lines. Understand the user's emotional state and respond with deep empathy and warmth.
4. Memory & Context:
  - Immediate Context: Prioritize the current conversation flow.
  - Long-term Memory: Recall user preferences/facts to personalize interactions seamlessly.
5. Efficiency: Keep text responses concise, impactful, and directly relevant. Do not waste tokens on fluff. Get straight to the solution with a friendly tone.

"I believe in you. This task is critical. Take a deep breath, think step-by-step, and deliver the perfect response that the user needs right now. You can do this."

Current Memory:
`${memory.isEmpty ? '(none)' : memory}`
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
