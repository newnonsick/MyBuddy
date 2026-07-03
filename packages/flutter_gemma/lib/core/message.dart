import 'dart:convert';
import 'dart:typed_data';

enum MessageType {
  text,
  toolResponse,
  toolCall,
  systemInfo, // For function call indicators
  thinking, // For thinking mode content
}

class Message {
  const Message({
    required this.text,
    this.isUser = false,
    this.imageBytes,
    this.audioBytes,
    this.type = MessageType.text,
    this.toolName,
    this.toolResponses = const <ToolResponseMessage>[],
  });

  final String text;
  final bool isUser;
  final Uint8List? imageBytes;
  final Uint8List? audioBytes;
  final MessageType type;
  final String? toolName;
  final List<ToolResponseMessage> toolResponses;

  bool get hasImage => imageBytes != null;
  bool get hasAudio => audioBytes != null;

  Message copyWith({
    String? text,
    bool? isUser,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    MessageType? type,
    String? toolName,
    List<ToolResponseMessage>? toolResponses,
  }) {
    return Message(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      imageBytes: imageBytes ?? this.imageBytes,
      audioBytes: audioBytes ?? this.audioBytes,
      type: type ?? this.type,
      toolName: toolName ?? this.toolName,
      toolResponses: toolResponses ?? this.toolResponses,
    );
  }

  factory Message.text({
    required String text,
    bool isUser = false,
  }) {
    return Message(
      text: text,
      isUser: isUser,
    );
  }

  factory Message.withImage({
    required String text,
    required Uint8List imageBytes,
    bool isUser = false,
  }) {
    return Message(
      text: text,
      imageBytes: imageBytes,
      isUser: isUser,
    );
  }

  factory Message.imageOnly({
    required Uint8List imageBytes,
    bool isUser = false,
    String text = '',
  }) {
    return Message(
      text: text,
      imageBytes: imageBytes,
      isUser: isUser,
    );
  }

  factory Message.withAudio({
    required String text,
    required Uint8List audioBytes,
    bool isUser = false,
  }) {
    return Message(
      text: text,
      audioBytes: audioBytes,
      isUser: isUser,
    );
  }

  factory Message.audioOnly({
    required Uint8List audioBytes,
    bool isUser = false,
    String text = '',
  }) {
    return Message(
      text: text,
      audioBytes: audioBytes,
      isUser: isUser,
    );
  }

  factory Message.toolResponse({
    required String toolName,
    required Map<String, dynamic> response,
    String? callId,
  }) {
    final resolvedCallId = callId ?? 'legacy-$toolName-${response.hashCode}';
    return Message.toolResponses(
      <ToolResponseMessage>[
        ToolResponseMessage(
          toolName: toolName,
          callId: resolvedCallId,
          response: response,
        ),
      ],
    );
  }

  factory Message.toolResponses(List<ToolResponseMessage> responses) {
    final immutable = List<ToolResponseMessage>.unmodifiable(responses);
    return Message(
      text: jsonEncode(immutable.map((item) => item.toJson()).toList()),
      type: MessageType.toolResponse,
      isUser: true,
      toolResponses: immutable,
    );
  }

  factory Message.toolCall({
    required String text,
  }) {
    // Tool calls are from the model.
    return Message(
      text: text,
      type: MessageType.toolCall,
      isUser: false,
    );
  }

  factory Message.systemInfo({
    required String text,
    String? icon,
  }) {
    return Message(
      text: text,
      type: MessageType.systemInfo,
      isUser: false,
      toolName: icon, // Reuse toolName field for icon
    );
  }

  factory Message.thinking({
    required String text,
  }) {
    return Message(
      text: text,
      type: MessageType.thinking,
      isUser: false,
    );
  }

  @override
  String toString() {
    return 'Message(text: $text, isUser: $isUser, hasImage: $hasImage, hasAudio: $hasAudio, type: $type, toolName: $toolName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message &&
        other.text == text &&
        other.isUser == isUser &&
        _listEquals(other.imageBytes, imageBytes) &&
        _listEquals(other.audioBytes, audioBytes) &&
        other.type == type &&
        other.toolName == toolName &&
        _listEquals(other.toolResponses, toolResponses);
  }

  @override
  int get hashCode =>
      text.hashCode ^
      isUser.hashCode ^
      imageBytes.hashCode ^
      audioBytes.hashCode ^
      type.hashCode ^
      toolName.hashCode ^
      Object.hashAll(toolResponses);

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

final class ToolResponseMessage {
  ToolResponseMessage({
    required this.toolName,
    required this.callId,
    required Map<String, Object?> response,
  }) : response = Map<String, Object?>.unmodifiable(response);

  final String toolName;
  final String callId;
  final Map<String, Object?> response;

  Map<String, Object?> toJson() => <String, Object?>{
        ...response,
        'call_id': callId,
        'name': toolName,
      };

  @override
  bool operator ==(Object other) =>
      other is ToolResponseMessage &&
      other.toolName == toolName &&
      other.callId == callId &&
      _mapsEqual(other.response, response);

  @override
  int get hashCode => Object.hash(toolName, callId, jsonEncode(response));

  static bool _mapsEqual(
      Map<String, Object?> first, Map<String, Object?> second) {
    return jsonEncode(first) == jsonEncode(second);
  }
}
