import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../google/google_auth_service.dart';
import '../google/google_calendar_service.dart';
import '../unity/unity_bridge.dart';
import 'animation_types.dart';

class FunctionCallHandler {
  FunctionCallHandler({
    required this.unityBridge,
    this.googleAuthService,
    this.googleCalendarService,
  });

  final UnityBridge unityBridge;
  final GoogleAuthService? googleAuthService;
  final GoogleCalendarService? googleCalendarService;

  Future<String> handle(FunctionCallResponse functionCall) async {
    switch (functionCall.name) {
      case 'animate_character':
        return _handleAnimateCharacter(functionCall);
      case 'create_calendar_event':
        return _handleCreateCalendarEvent(functionCall);
      default:
        return functionCall.toString();
    }
  }

  Future<String> _handleAnimateCharacter(FunctionCallResponse call) async {
    final animationName = call.args['animation'] as String?;
    final animateCount = call.args['animate_count'] as int? ?? 1;
    final responseText = call.args['response_text'] as String?;

    final animation = CharacterAnimation.fromName(animationName);
    if (animation != null) {
      await _playAnimation(animation, count: animateCount);
    }

    return responseText ?? call.toString();
  }

  Future<void> _playAnimation(
    CharacterAnimation animation, {
    int count = 1,
  }) async {
    final clampedCount = count.clamp(1, 10);

    if (animation == CharacterAnimation.jump) {
      for (int i = 0; i < clampedCount; i++) {
        unawaited(unityBridge.playAnimation(animation.animationIndex));
        if (i < clampedCount - 1) {
          await Future.delayed(animation.duration);
        }
      }
    } else {
      unawaited(unityBridge.playAnimation(animation.animationIndex));
    }
  }

  Future<String> _handleCreateCalendarEvent(FunctionCallResponse call) async {
    final calendarService = googleCalendarService;
    final authService = googleAuthService;

    if (calendarService == null ||
        authService == null ||
        !authService.isSignedIn) {
      return call.args['response_text'] as String? ??
          'Sorry, I couldn\'t create the event. Please sign in to Google Calendar first.';
    }

    try {
      final title = call.args['title'] as String?;
      final description = call.args['description'] as String?;
      final startDateStr = call.args['start_date'] as String?;
      final endDateStr = call.args['end_date'] as String?;
      final isAllDay = call.args['is_all_day'] as bool? ?? false;
      final location = call.args['location'] as String?;
      final responseText = call.args['response_text'] as String?;

      if (title == null || startDateStr == null) {
        return responseText ??
            'Sorry, I need at least a title and date to create an event.';
      }

      final startTime = DateTime.tryParse(startDateStr);
      if (startTime == null) {
        return responseText ?? 'Sorry, I couldn\'t understand the date format.';
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
        return responseText ?? 'I\'ve added "$title" to your calendar.';
      } else {
        return responseText ??
            'Sorry, I couldn\'t create the event: ${result.error}';
      }
    } catch (e) {
      return call.args['response_text'] as String? ??
          'Sorry, something went wrong while creating the event.';
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
