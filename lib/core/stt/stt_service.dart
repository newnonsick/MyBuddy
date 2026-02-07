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
    int threads = 6,
  }) async {
    // We use the low-level Whisper entry point so we can provide a custom model
    // path (quantized GGML bin), while still leveraging whisper_ggml_plus.
    final whisper = Whisper(
      model: _guessModelFromPath(modelPath),
      modelDir: p.dirname(modelPath),
    );

    try {
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          language: lang,
          isTranslate: isTranslate,
          threads: threads,
          isNoTimestamps: true,
          splitOnWord: false,
          isRealtime: true,
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
    // Heuristic only; modelPath is authoritative for the engine.
    if (lower.contains('large-v3-turbo')) return WhisperModel.largeV3Turbo;
    if (lower.contains('large-v3')) return WhisperModel.large;
    if (lower.contains('medium')) return WhisperModel.medium;
    if (lower.contains('small')) return WhisperModel.small;
    if (lower.contains('base')) return WhisperModel.base;
    if (lower.contains('tiny')) return WhisperModel.tiny;
    return WhisperModel.base;
  }
}
