import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> speakText(String text) async {
    final safe = text.trim();
    if (safe.isEmpty) return;

    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.stop();
    await _tts.speak(safe);
  }

  Future<String?> _waitForStableFile(
    String filePath, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    int? lastSize;
    int stableCount = 0;
    const minWavBytes = 44 + 128;

    while (stopwatch.elapsed < timeout) {
      final file = File(filePath);
      if (await file.exists()) {
        final length = await file.length();

        if (length >= minWavBytes) {
          if (lastSize != null && length == lastSize) {
            stableCount++;
          } else {
            stableCount = 0;
          }

          if (stableCount >= 3) return filePath;
        }

        lastSize = length;
      }

      await Future<void>.delayed(
        stopwatch.elapsed < const Duration(seconds: 2)
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 160),
      );
    }

    return null;
  }

  Future<String> synthesizeToWavFile({
    required String text,
    String fileNameBase = 'tts',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      await (_tts as dynamic).awaitSynthCompletion(true);
    } catch (_) {}

    final List<Directory> candidateDirs = <Directory>[];
    candidateDirs.add(await getTemporaryDirectory());

    try {
      final externalCaches = await getExternalCacheDirectories();
      if (externalCaches != null) {
        candidateDirs.addAll(externalCaches);
      }
    } catch (_) {}

    final attempts = <String>[];
    Object? lastError;

    for (final dir in candidateDirs.toSet()) {
      final filePath = p.join(
        dir.path,
        '${fileNameBase}_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      try {
        await File(filePath).delete();
      } catch (_) {}

      try {
        final synthResult = await _tts.synthesizeToFile(text, filePath, true);
        attempts.add('path=$filePath result=$synthResult');

        final producedPath = await _waitForStableFile(
          filePath,
          timeout: timeout,
        );
        if (producedPath != null) return producedPath;
      } catch (e) {
        lastError = e;
        attempts.add('path=$filePath error=$e');
      }
    }

    String diagnostics = '';
    try {
      final lastAttempt = attempts.isNotEmpty ? attempts.last : '';
      final match = RegExp(r'path=([^ ]+)').firstMatch(lastAttempt);
      final lastPath = match?.group(1);
      if (lastPath != null) {
        final file = File(lastPath);
        diagnostics = await file.exists()
            ? ' exists=true size=${await file.length()}'
            : ' exists=false';
      }
    } catch (e) {
      diagnostics = ' stat_failed=$e';
    }

    throw StateError(
      'TTS did not produce a WAV file in time. attempts=${attempts.join(" | ")}${lastError != null ? " lastError=$lastError" : ""}$diagnostics timeout=${timeout.inMilliseconds}ms',
    );
  }

  Future<void> stop() => _tts.stop();

  Future<void> dispose() async {
    await _tts.stop();
  }
}
