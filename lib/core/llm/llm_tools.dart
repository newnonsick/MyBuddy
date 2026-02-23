import 'package:flutter_gemma/flutter_gemma.dart';

import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';

abstract final class LlmTools {
  static const Tool animateCharacter = Tool(
    name: 'animate_character',
    description: 'Makes the character perform a specified animation.',
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
              'Number of times to perform the animation (only for certain animations). Default is 1.',
        },
      },
      'required': ['animation', 'animate_count'],
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
      },
      'required': ['title', 'start_date'],
    },
  );

  static List<Tool> getAvailableTools({
    GoogleAuthService? googleAuthService,
    GoogleCalendarService? googleCalendarService,
  }) {
    final tools = <Tool>[animateCharacter];

    if ((googleAuthService?.isSignedIn ?? false) &&
        googleCalendarService != null) {
      tools.add(createCalendarEvent);
    }

    return tools;
  }
}
