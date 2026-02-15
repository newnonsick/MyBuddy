import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

class SttService {
  const SttService();

  Future<String?> transcribe({
    required String modelPath,
    required String audioPath,
    required String lang,
    required bool isTranslate,
    int? threads,
  }) async {
    final whisper = Whisper(
      model: _guessModelFromPath(modelPath),
      modelDir: p.dirname(modelPath),
    );

    final selectedThreads = threads ?? _defaultThreads();

    try {
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          language: lang,
          isTranslate: isTranslate,
          threads: selectedThreads,
          isNoTimestamps: true,
          splitOnWord: false,
          isRealtime: false,
          diarize: false,
          speedUp: false,
        ),
        modelPath: modelPath,
      );

      final text = response.text.trim();
      if (text.isEmpty) return null;
      return text;
    } catch (e) {
      debugPrint('STT transcribe failed: $e');
      rethrow;
    }
  }

  WhisperModel _guessModelFromPath(String modelPath) {
    final lower = modelPath.toLowerCase();
    if (lower.contains('large-v3-turbo')) return WhisperModel.largeV3Turbo;
    if (lower.contains('large-v3')) return WhisperModel.large;
    if (lower.contains('medium')) return WhisperModel.medium;
    if (lower.contains('small')) return WhisperModel.small;
    if (lower.contains('base')) return WhisperModel.base;
    if (lower.contains('tiny')) return WhisperModel.tiny;
    return WhisperModel.base;
  }

  int _defaultThreads() {
    final cpuCount = Platform.numberOfProcessors;
    if (cpuCount <= 2) return 2;
    if (cpuCount <= 4) return 3;
    return (cpuCount - 1).clamp(4, 8);
  }
}
