import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../app/app_controller.dart';

class OverlayChatRelay {
  OverlayChatRelay({required this.appController});

  final AppController appController;
  StreamSubscription<dynamic>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = FlutterOverlayWindow.overlayListener.listen(_onMessage);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onMessage(dynamic raw) async {
    if (raw is! String || raw.trim().isEmpty) return;

    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;

      final type = map['type'] as String?;

      if (type == 'chat_request') {
        await _handleChatRequest(map);
      }
    } catch (e) {
      debugPrint('OverlayChatRelay: error handling message: $e');
    }
  }

  Future<void> _handleChatRequest(Map<String, dynamic> map) async {
    final text = (map['text'] as String?)?.trim();
    final requestId = map['requestId'] as String? ?? '';

    if (text == null || text.isEmpty) {
      await _sendResponse(requestId: requestId, error: 'Empty message');
      return;
    }

    if (!appController.llmInstalled) {
      await _sendResponse(
        requestId: requestId,
        error: 'No LLM model loaded. Open the app and select a model first.',
      );
      return;
    }

    try {
      final reply = await appController.chatOnce(text);
      await _sendResponse(requestId: requestId, reply: reply.trim());
    } catch (e) {
      await _sendResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _sendResponse({
    required String requestId,
    String? reply,
    String? error,
  }) async {
    final payload = <String, Object>{
      'type': 'chat_response',
      'requestId': requestId,
      if (reply != null) 'reply': reply,
      if (error != null) 'error': error,
    };
    await FlutterOverlayWindow.shareData(jsonEncode(payload));
  }
}
