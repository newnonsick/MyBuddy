import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../app/app_controller.dart';
import '../../app/model_controller.dart';
import '../llm/llm_service.dart';
import '../memory/memory_service.dart';

/// A lightweight [AppController] substitute for the overlay engine.
///
/// Instead of loading an LLM model in-process, it relays chat requests
/// to the main app engine via [FlutterOverlayWindow.shareData] IPC and
/// waits for a `chat_response` payload back.
class OverlayAppProxy extends AppController {
  OverlayAppProxy({
    required super.models,
    required super.llm,
    required super.memory,
  });

  StreamSubscription<dynamic>? _responseSubscription;
  final Map<String, Completer<String>> _pending = {};
  int _nextId = 0;

  /// Call once to start listening for responses from the main app.
  void startListening(Stream<dynamic> overlayStream) {
    _responseSubscription?.cancel();
    _responseSubscription = overlayStream.listen(_onPayload);
  }

  void _onPayload(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;
      if (map['type'] != 'chat_response') return;

      final requestId = map['requestId'] as String? ?? '';
      final completer = _pending.remove(requestId);
      if (completer == null) return;

      final error = map['error'] as String?;
      if (error != null) {
        completer.completeError(Exception(error));
      } else {
        completer.complete((map['reply'] as String?) ?? '');
      }
    } catch (e) {
      debugPrint('OverlayAppProxy: failed to parse response: $e');
    }
  }

  /// The overlay is always "installed" because the main app handles the LLM.
  @override
  bool get llmInstalled => true;

  @override
  bool get installingLlm => false;

  @override
  String? get llmError => null;

  /// Relay the chat to the main app and wait for a response.
  @override
  Future<String> chatOnce(String userText) async {
    final id = '${_nextId++}';
    final completer = Completer<String>();
    _pending[id] = completer;

    final payload = <String, Object>{
      'type': 'chat_request',
      'text': userText,
      'requestId': id,
    };

    await FlutterOverlayWindow.shareData(jsonEncode(payload));

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('LLM response timed out');
      },
    );
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
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('Overlay closed'));
      }
    }
    _pending.clear();
  }
}
