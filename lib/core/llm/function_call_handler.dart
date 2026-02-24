import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';
import '../memory/memory_service.dart';
import '../unity/unity_bridge.dart';
import 'animation_types.dart';

class FunctionCallHandler {
  FunctionCallHandler({
    required this.unityBridge,
    required this.memoryService,
    this.googleAuthService,
    this.googleCalendarService,
  });

  final UnityBridge unityBridge;
  final MemoryService memoryService;
  final GoogleAuthService? googleAuthService;
  final GoogleCalendarService? googleCalendarService;

  Future<Map<String, dynamic>> handle(FunctionCallResponse functionCall) async {
    switch (functionCall.name) {
      case 'animate_character':
        return _handleAnimateCharacter(functionCall);
      case 'create_calendar_event':
        return _handleCreateCalendarEvent(functionCall);
      default:
        return {'error': 'Unknown function: ${functionCall.name}'};
    }
  }

  Future<Map<String, dynamic>> _handleAnimateCharacter(
    FunctionCallResponse call,
  ) async {
    final animationName = call.args['animation'] as String?;
    final animateCount = call.args['animate_count'] as int? ?? 1;

    final animation = CharacterAnimation.fromName(animationName);
    if (animation != null) {
      unawaited(_playAnimation(animation, count: animateCount));
      return {
        'status': 'success',
        'message': 'Animation "$animationName" played $animateCount time(s)',
      };
    }

    return {'error': 'Unknown animation: $animationName'};
  }

  Future<void> _playAnimation(
    CharacterAnimation animation, {
    int count = 1,
  }) async {
    final clampedCount = count.clamp(1, 10);

    for (int i = 0; i < clampedCount; i++) {
      unawaited(unityBridge.playAnimation(animation.animationIndex));
      if (i < clampedCount - 1) {
        await Future.delayed(animation.duration);
      }
    }
  }

  Future<Map<String, dynamic>> _handleCreateCalendarEvent(
    FunctionCallResponse call,
  ) async {
    final calendarService = googleCalendarService;
    final authService = googleAuthService;

    if (calendarService == null ||
        authService == null ||
        !authService.isSignedIn) {
      return {'error': 'Google Calendar not available. Please sign in first.'};
    }

    try {
      final title = call.args['title'] as String?;
      final description = call.args['description'] as String?;
      final startDateStr = call.args['start_date'] as String?;
      final endDateStr = call.args['end_date'] as String?;
      final isAllDay = call.args['is_all_day'] as bool? ?? false;
      final location = call.args['location'] as String?;

      if (title == null || startDateStr == null) {
        return {'error': 'Missing required fields: title and start_date'};
      }

      final startTime = DateTime.tryParse(startDateStr);
      if (startTime == null) {
        return {'error': 'Invalid date format: $startDateStr'};
      }

      final endTime = _calculateEndTime(
        startTime: startTime,
        endDateStr: endDateStr,
        isAllDay: isAllDay,
      );

      final result = await calendarService.createEvent(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
      );

      if (result.isSuccess) {
        return {
          'status': 'success',
          'message': 'Event "$title" created',
          'title': title,
          'start_date': startDateStr,
          if (endDateStr != null) 'end_date': endDateStr,
          if (location != null) 'location': location,
        };
      } else {
        return {'error': 'Failed to create event: ${result.error}'};
      }
    } catch (e) {
      return {'error': 'Error creating calendar event: $e'};
    }
  }

  DateTime _calculateEndTime({
    required DateTime startTime,
    required String? endDateStr,
    required bool isAllDay,
  }) {
    if (endDateStr != null) {
      return DateTime.tryParse(endDateStr) ??
          startTime.add(const Duration(hours: 1));
    }

    return isAllDay
        ? startTime.add(const Duration(days: 1))
        : startTime.add(const Duration(hours: 1));
  }
}
