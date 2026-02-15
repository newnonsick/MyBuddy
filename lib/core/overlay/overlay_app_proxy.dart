import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../app/app_controller.dart';
import '../stt/stt_service.dart';

class OverlayAppProxy extends AppController {
  OverlayAppProxy({
    required super.models,
    required super.llm,
    required super.memory,
  });

  StreamSubscription<dynamic>? _responseSubscription;
  final Map<String, Completer<String>> _chatPending = {};
  final Map<String, Completer<String?>> _sttPending = {};
  bool _isListening = false;

  void startListening(Stream<dynamic> overlayStream) {
    _responseSubscription?.cancel();
    _isListening = true;
    _responseSubscription = overlayStream.listen(
      _onPayload,
      onError: (e) => debugPrint('OverlayAppProxy: stream error: $e'),
    );
  }

  void _onPayload(dynamic raw) {
    try {
      final map = _parsePayload(raw);
      if (map == null) return;

      final type = map['type'] as String?;
      if (type == 'chat_response') {
        _handleChatResponse(map);
      } else if (type == 'stt_response') {
        _handleSttResponse(map);
      }
    } catch (e) {
      debugPrint('OverlayAppProxy: failed to parse response: $e');
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

  void _handleChatResponse(Map<String, dynamic> map) {
    final requestId = '${map['requestId'] ?? ''}';
    final completer = _chatPending.remove(requestId);
    if (completer == null) {
      debugPrint('OverlayAppProxy: no pending chat for requestId=$requestId');
      return;
    }

    final error = map['error'] as String?;
    if (error != null) {
      completer.completeError(Exception(error));
    } else {
      completer.complete((map['reply'] as String?) ?? '');
    }
  }

  void _handleSttResponse(Map<String, dynamic> map) {
    final requestId = '${map['requestId'] ?? ''}';
    final completer = _sttPending.remove(requestId);
    if (completer == null) {
      debugPrint('OverlayAppProxy: no pending STT for requestId=$requestId');
      return;
    }

    final error = map['error'] as String?;
    if (error != null) {
      completer.completeError(Exception(error));
    } else {
      completer.complete(map['text'] as String?);
    }
  }

  @override
  bool get llmInstalled => true;

  @override
  bool get installingLlm => false;

  @override
  String? get llmError => null;

  @override
  Future<String> chatOnce(String userText) async {
    if (!_isListening) {
      throw StateError('Overlay channel is not ready yet. Please try again.');
    }

    final id = _createRequestId();
    final completer = Completer<String>();
    _chatPending[id] = completer;

    final payload = <String, Object>{
      'type': 'chat_request',
      'text': userText,
      'requestId': id,
    };

    debugPrint('OverlayAppProxy.chatOnce: sending chat_request id=$id');

    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      _chatPending.remove(id);
      debugPrint('OverlayAppProxy.chatOnce: shareData failed: $e');
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _chatPending.remove(id);
        debugPrint('OverlayAppProxy.chatOnce: timed out id=$id');
        throw TimeoutException('LLM response timed out');
      },
    );
  }

  Future<String?> transcribeAudio({
    required String modelPath,
    required String audioPath,
    required String lang,
    required bool isTranslate,
  }) async {
    if (!_isListening) {
      throw StateError('Overlay channel is not ready yet.');
    }

    final id = _createRequestId();
    final completer = Completer<String?>();
    _sttPending[id] = completer;

    final payload = <String, Object>{
      'type': 'stt_request',
      'requestId': id,
      'audioPath': audioPath,
      'modelPath': modelPath,
      'lang': lang,
      'isTranslate': isTranslate,
    };

    debugPrint('OverlayAppProxy.transcribeAudio: sending stt_request id=$id');

    try {
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (e) {
      _sttPending.remove(id);
      debugPrint('OverlayAppProxy.transcribeAudio: shareData failed: $e');
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _sttPending.remove(id);
        debugPrint('OverlayAppProxy.transcribeAudio: timed out id=$id');
        throw TimeoutException('STT transcription timed out');
      },
    );
  }

  String _createRequestId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final hash = identityHashCode(this);
    return '$micros-$hash';
  }

  @override
  Future<void> startup() async {
    // No-op — overlay doesn't load models.
  }

  @override
  Future<void> activateSelectedModel() async {
    // No-op — overlay relies on main app.
  }

  void disposeRelay() {
    _responseSubscription?.cancel();
    _responseSubscription = null;
    _isListening = false;
    for (final c in _chatPending.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('Overlay closed'));
      }
    }
    _chatPending.clear();
    for (final c in _sttPending.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('Overlay closed'));
      }
    }
    _sttPending.clear();
  }
}

class OverlaySttService extends SttService {
  const OverlaySttService(this._proxy);

  final OverlayAppProxy _proxy;

  @override
  Future<String?> transcribe({
    required String modelPath,
    required String audioPath,
    required String lang,
    required bool isTranslate,
    int? threads,
  }) {
    return _proxy.transcribeAudio(
      modelPath: modelPath,
      audioPath: audioPath,
      lang: lang,
      isTranslate: isTranslate,
    );
  }
}
