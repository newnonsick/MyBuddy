import 'package:flutter/foundation.dart';

@immutable
class ChatLine {
  const ChatLine({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _CurrentDateTime();

  factory ChatLine.user(String text) =>
      ChatLine(text: text, isUser: true, timestamp: DateTime.now());

  factory ChatLine.assistant(String text) =>
      ChatLine(text: text, isUser: false, timestamp: DateTime.now());

  final String text;
  final bool isUser;
  final DateTime timestamp;

  bool get isAssistant => !isUser;
  String get role => isUser ? 'user' : 'assistant';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatLine &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(text, isUser, timestamp);

  @override
  String toString() =>
      'ChatLine(role: $role, text: ${text.length > 50 ? '${text.substring(0, 50)}...' : text})';
}

class _CurrentDateTime implements DateTime {
  const _CurrentDateTime();

  DateTime get _now => DateTime.now();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(_now.noSuchMethod, [invocation]);
}
