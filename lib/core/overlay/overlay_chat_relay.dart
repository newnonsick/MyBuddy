import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../app/app_controller.dart';
import '../stt/stt_service.dart';

class OverlayChatRelay {
  OverlayChatRelay({required this.appController, required this.sttService});

  final AppController appController;
  final SttService sttService;
  Future<void>? _ensureReadyFuture;

  static const _channel = BasicMessageChannel<dynamic>(
    'x-slayer/overlay_messenger',
    JSONMessageCodec(),
  );

  void start() {
    _channel.setMessageHandler((dynamic message) async {
      debugPrint(
        'OverlayChatRelay: raw handler received '
        'type=${message.runtimeType}',
      );
      await _onMessage(message);
      return message;
    });
    debugPrint('OverlayChatRelay: started listening (direct handler)');
  }

  void dispose() {
    _channel.setMessageHandler(null);
  }

  Future<void> _onMessage(dynamic raw) async {
    try {
      final map = _parsePayload(raw);
      if (map == null) return;

      final type = map['type'] as String?;
      debugPrint('OverlayChatRelay: received message type=$type');

      if (type == 'chat_request') {
        await _handleChatRequest(map);
      } else if (type == 'stt_request') {
        await _handleSttRequest(map);
      }
    } catch (e) {
      debugPrint('OverlayChatRelay: error handling message: $e');
    }
  }

  static Map<String, dynamic>? _parsePayload(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  Future<void> _handleChatRequest(Map<String, dynamic> map) async {
    final text = (map['text'] as String?)?.trim();
    final requestId = map['requestId'] as String? ?? '';

    debugPrint('OverlayChatRelay: chat_request id=$requestId text=$text');

    if (text == null || text.isEmpty) {
      await _sendResponse(requestId: requestId, error: 'Empty message');
      return;
    }

    try {
      await _ensureAppReadyForOverlayChat();

      if (!appController.llmInstalled) {
        await _sendResponse(
          requestId: requestId,
          error:
              'No LLM model loaded. Open the app and select a model in Settings.',
        );
        return;
      }

      debugPrint('OverlayChatRelay: calling chatOnce...');
      final reply = await appController.chatOnce(text);
      debugPrint('OverlayChatRelay: chatOnce replied (${reply.length} chars)');
      await _sendResponse(requestId: requestId, reply: reply.trim());
    } catch (e) {
      debugPrint('OverlayChatRelay: chatOnce error: $e');
      await _sendResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _handleSttRequest(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String? ?? '';
    final audioPath = map['audioPath'] as String?;
    final modelPath = map['modelPath'] as String?;
    final lang = map['lang'] as String? ?? 'auto';
    final isTranslate = map['isTranslate'] as bool? ?? true;

    debugPrint('OverlayChatRelay: stt_request id=$requestId audio=$audioPath');

    if (audioPath == null || modelPath == null) {
      await _sendSttResponse(
        requestId: requestId,
        error: 'Missing audio or model path',
      );
      return;
    }

    try {
      final text = await sttService.transcribe(
        modelPath: modelPath,
        audioPath: audioPath,
        lang: lang,
        isTranslate: isTranslate,
      );
      debugPrint(
        'OverlayChatRelay: STT result: '
        '${text != null ? text.substring(0, text.length.clamp(0, 80)) : 'null'}',
      );
      await _sendSttResponse(requestId: requestId, text: text);
    } catch (e) {
      debugPrint('OverlayChatRelay: STT error: $e');
      await _sendSttResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _ensureAppReadyForOverlayChat() {
    final inFlight = _ensureReadyFuture;
    if (inFlight != null) return inFlight;

    final future = _doEnsureAppReadyForOverlayChat();
    _ensureReadyFuture = future;
    return future.whenComplete(() {
      if (identical(_ensureReadyFuture, future)) {
        _ensureReadyFuture = null;
      }
    });
  }

  Future<void> _doEnsureAppReadyForOverlayChat() async {
    await appController.startup();

    if (appController.llmInstalled || appController.installingLlm) {
      return;
    }

    if (appController.models.selectedInstalledModel == null) {
      final lastUsedId = appController.models.lastUsedModelId;
      if (lastUsedId != null && lastUsedId.trim().isNotEmpty) {
        appController.models.setPendingSelection(lastUsedId);
        await appController.models.commitSelection();
      }
    }

    if (appController.models.selectedInstalledModel != null) {
      await appController.activateSelectedModel();
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
    debugPrint('OverlayChatRelay: sending chat_response id=$requestId');
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      debugPrint('OverlayChatRelay: chat_response send failed: $e');
    }
  }

  Future<void> _sendSttResponse({
    required String requestId,
    String? text,
    String? error,
  }) async {
    final payload = <String, Object>{
      'type': 'stt_response',
      'requestId': requestId,
      if (text != null) 'text': text,
      if (error != null) 'error': error,
    };
    debugPrint('OverlayChatRelay: sending stt_response id=$requestId');
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      debugPrint('OverlayChatRelay: stt_response send failed: $e');
    }
  }
}
