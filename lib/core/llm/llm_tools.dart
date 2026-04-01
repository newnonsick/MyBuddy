import 'package:flutter_gemma/flutter_gemma.dart';

import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';

abstract final class LlmTools {
  static const Tool animateCharacter = Tool(
    name: 'perform_avatar_action',
    description:
        'Instructs the your own avatar to perform a specific action or animation to interact with the user in a more engaging and dynamic way. Use this tool when you want to express emotions, reactions, or simply have fun with the user through your avatar\'s movements. You can specify the type of animation and how many times it should be performed.',
    parameters: {
      'type': 'object',
      'properties': {
        'animation': {
          'type': 'string',
          'description': 'Animation to perform.',
          'enum': [
            'jump',
            'spin',
            'clap',
            'thankful',
            'greet',
            'dance',
            'chicken_dance',
            'think',
          ],
        },
        'animate_count': {
          'type': 'int',
          'description':
              'Number of times to perform the animation. Default is 1.',
        },
        'response_text': {
          'type': 'string',
          'description':
              'Text response that responds to the user\'s input with empathy and relevance',
        },
      },
      'required': ['animation', 'animate_count', 'response_text'],
    },
  );

  static const Tool createCalendarEvent = Tool(
    name: 'create_calendar_event',
    description:
        'Creates a new event on the user\'s Google Calendar. Use this when the user wants to schedule an appointment, reminder, meeting, or any calendar event. Parse natural language dates/times from the user\'s request.',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'description': 'The title or name of the event.',
        },
        'description': {
          'type': 'string',
          'description': 'Optional description or notes for the event.',
        },
        'start_date': {
          'type': 'string',
          'description':
              'The start date and time in ISO 8601 format (e.g., "2026-02-15T14:00:00"). For all-day events, use date only (e.g., "2026-02-15").',
        },
        'end_date': {
          'type': 'string',
          'description':
              'The end date and time in ISO 8601 format. For all-day events, use date only. If not specified, defaults to 1 hour after start.',
        },
        'is_all_day': {
          'type': 'boolean',
          'description': 'Whether this is an all-day event. Default is false.',
        },
        'location': {
          'type': 'string',
          'description': 'Optional location for the event.',
        },
        'response_text': {
          'type': 'string',
          'description':
              'Text response that responds to the user\'s input with empathy and relevance',
        },
      },
      'required': ['title', 'start_date', 'response_text'],
    },
  );

  static const Tool updateAssistantSoul = Tool(
    name: 'update_assistant_soul',
    description:
        'Update SOUL memory that represent your core personality, values, behavior rules, and boundaries',
    parameters: {
      'type': 'object',
      'properties': {
        'response_text': {
          'type': 'string',
          'description':
              'Text response that responds to the user\'s input with empathy and relevance',
        },
      },
      'required': ['response_text'],
    },
  );

  static const Tool updateAssistantIdentity = Tool(
    name: 'update_assistant_identity',
    description:
        'Update INDENTITY memory that represents your name, tone, style, and presentation',
    parameters: {
      'type': 'object',
      'properties': {
        'response_text': {
          'type': 'string',
          'description':
              'Text response that responds to the user\'s input with empathy and relevance',
        },
      },
      'required': ['response_text'],
    },
  );

  static const Tool updateUserMemory = Tool(
    name: 'update_user_memory',
    description:
        'Update USER memory that represents user profile, preferences, goals, and interaction style, and context',
    parameters: {
      'type': 'object',
      'properties': {
        'response_text': {
          'type': 'string',
          'description':
              'Text response that responds to the user\'s input with empathy and relevance',
        },
      },
      'required': ['response_text'],
    },
  );

  static List<Tool> getAvailableTools({
    GoogleAuthService? googleAuthService,
    GoogleCalendarService? googleCalendarService,
    bool isAutoMemoryUpdateAllowed = false,
  }) {
    final tools = <Tool>[animateCharacter];

    if (isAutoMemoryUpdateAllowed) {
      tools.addAll(<Tool>[
        updateAssistantIdentity,
        updateAssistantSoul,
        updateUserMemory,
      ]);
    }

    if ((googleAuthService?.isSignedIn ?? false) &&
        googleCalendarService != null) {
      tools.add(createCalendarEvent);
    }

    return tools;
  }
}
