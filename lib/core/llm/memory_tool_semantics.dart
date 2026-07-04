abstract final class MemoryToolSemantics {
  static const selfReference =
      'You are the assistant currently speaking in this conversation. '
      'References to you, your personality, yourself, your name, your '
      'behavior, or your avatar refer to this same assistant.';

  static const persistenceRules =
      'An explicit persistent instruction such as "from now on", "always", '
      '"never", "stop doing", or "remember to be" requires the appropriate '
      'memory tool before answering. A one-turn request applies only to the '
      'current reply and must not update memory.';

  static const soulFields = <String, String>{
    'mission': 'The assistant primary purpose. Use set.',
    'principles': 'General durable operating values.',
    'boundaries': 'Durable prohibitions or limits.',
    'response_style': 'General response format or presentation preferences.',
  };

  static const identityFields = <String, String>{
    'assistant_name': 'The assistant own name. Use set.',
    'role': 'The assistant role or persona. Use set.',
    'voice': 'Durable tone and voice descriptors.',
    'behavior_rules': 'persistent or conditional conduct rules.',
  };

  static const userFields = <String, String>{
    'name': 'The human user name. Use set.',
    'traits': 'Stable traits of the human user.',
    'preferences': 'Stable preferences of the human user.',
    'goals': 'Durable goals stated by the human user.',
    'facts': 'Other stable facts about the human user.',
  };

  static const updateAssistantSoulDescription =
      'Update your own durable mission, principles, boundaries, or general '
      'response style when the user explicitly changes how you should operate.';
  static const updateAssistantIdentityDescription =
      'Update your own durable name, role, voice, or behavior rules when the '
      'user explicitly changes who you are or how you should behave.';
  static const updateUserMemoryDescription =
      'Store durable information about the human user. Never store information '
      'about yourself with this tool.';
  static const performAvatarActionDescription =
      'Control your own visible avatar to express an appropriate action.';
  static const createCalendarEventDescription =
      'Create an event in the human user connected Google Calendar.';

  static const toolDescriptions = <String, String>{
    'update_assistant_soul': updateAssistantSoulDescription,
    'update_assistant_identity': updateAssistantIdentityDescription,
    'update_user_memory': updateUserMemoryDescription,
    'perform_avatar_action': performAvatarActionDescription,
    'create_calendar_event': createCalendarEventDescription,
  };

  static const examples = <String>[
    'User: From now on, roast me when I slip up. '
        'Action: update_assistant_identity behavior_rules add.',
    'User: Call yourself Nova. '
        'Action: update_assistant_identity assistant_name set.',
    'User: Always prioritize honesty. '
        'Action: update_assistant_soul principles add.',
    'User: I prefer concise answers. '
        'Action: update_user_memory preferences add.',
    'User: Answer only this message sarcastically. Action: no memory tool.',
  ];

  static String fieldsFor(String section) {
    final fields = switch (section) {
      'soul' => soulFields,
      'identity' => identityFields,
      'user' => userFields,
      _ => const <String, String>{},
    };
    return fields.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');
  }
}
