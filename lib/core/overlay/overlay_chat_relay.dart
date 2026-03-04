import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../app/app_controller.dart';
import '../stt/stt_service.dart';
import 'package:path_provider/path_provider.dart';

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
      } else if (type == 'recording_start_request') {
        await _handleRecordingStartRequest(map);
      } else if (type == 'recording_stop_request') {
        await _handleRecordingStopRequest(map);
      } else if (type == 'recording_cancel_request') {
        await _handleRecordingCancelRequest();
      } else if (type == 'model_switch_request') {
        await _handleModelSwitchRequest(map);
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
      appController.beginTranscribing();
      String? text;
      try {
        text = await sttService.transcribe(
          modelPath: modelPath,
          audioPath: audioPath,
          lang: lang,
          isTranslate: isTranslate,
        );
      } finally {
        appController.endTranscribing();
      }
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

  Future<void> _handleRecordingStartRequest(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String? ?? '';
    debugPrint('OverlayChatRelay: recording_start_request id=$requestId');

    try {
      final temp = await getTemporaryDirectory();
      final dir = '${temp.path}/stt_recordings';
      final fileName = 'rec_${DateTime.now().toUtc().millisecondsSinceEpoch}.wav';
      final outPath = '$dir/$fileName';

      final path = await FlutterOverlayWindow.startOverlayRecording(outPath);
      debugPrint('OverlayChatRelay: native recording started at $path');
      await _sendRecordingResponse(requestId: requestId, path: path ?? outPath);
    } catch (e) {
      debugPrint('OverlayChatRelay: recording start error: $e');
      await _sendRecordingResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _handleRecordingStopRequest(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String? ?? '';
    debugPrint('OverlayChatRelay: recording_stop_request id=$requestId');

    try {
      final path = await FlutterOverlayWindow.stopOverlayRecording();
      debugPrint('OverlayChatRelay: native recording stopped at $path');
      await _sendRecordingResponse(
        requestId: requestId,
        path: path ?? '',
      );
    } catch (e) {
      debugPrint('OverlayChatRelay: recording stop error: $e');
      await _sendRecordingResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _handleRecordingCancelRequest() async {
    debugPrint('OverlayChatRelay: recording_cancel_request');
    try {
      await FlutterOverlayWindow.cancelOverlayRecording();
    } catch (e) {
      debugPrint('OverlayChatRelay: recording cancel error: $e');
    }
  }

  Future<void> _sendRecordingResponse({
    required String requestId,
    String? path,
    String? error,
  }) async {
    final payload = <String, Object>{
      'type': 'recording_response',
      'requestId': requestId,
      if (path != null) 'path': path,
      if (error != null) 'error': error,
    };
    debugPrint('OverlayChatRelay: sending recording_response id=$requestId');
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      debugPrint('OverlayChatRelay: recording_response send failed: $e');
    }
  }

  Future<void> _handleModelSwitchRequest(Map<String, dynamic> map) async {
    final requestId = map['requestId'] as String? ?? '';
    final modelId = map['modelId'] as String?;
    debugPrint(
      'OverlayChatRelay: model_switch_request id=$requestId model=$modelId',
    );

    if (modelId == null || modelId.trim().isEmpty) {
      await _sendModelSwitchResponse(
        requestId: requestId,
        error: 'Missing model ID',
      );
      return;
    }

    try {
      await _ensureAppReadyForOverlayChat();
      appController.models.setPendingSelection(modelId);
      await appController.models.commitSelection();
      await appController.activateSelectedModel();
      debugPrint('OverlayChatRelay: model switched to $modelId');
      await _sendModelSwitchResponse(requestId: requestId);
    } catch (e) {
      debugPrint('OverlayChatRelay: model switch error: $e');
      await _sendModelSwitchResponse(requestId: requestId, error: '$e');
    }
  }

  Future<void> _sendModelSwitchResponse({
    required String requestId,
    String? error,
  }) async {
    final payload = <String, Object>{
      'type': 'model_switch_response',
      'requestId': requestId,
      if (error != null) 'error': error,
    };
    debugPrint(
      'OverlayChatRelay: sending model_switch_response id=$requestId',
    );
    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      debugPrint(
        'OverlayChatRelay: model_switch_response send failed: $e',
      );
    }
  }
}
