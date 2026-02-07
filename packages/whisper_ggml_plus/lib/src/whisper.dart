import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:whisper_ggml_plus/src/models/whisper_model.dart';

import 'models/requests/abort_request.dart';
import 'models/requests/transcribe_request.dart';
import 'models/requests/transcribe_request_dto.dart';
import 'models/requests/version_request.dart';
import 'models/responses/whisper_transcribe_response.dart';
import 'models/responses/whisper_version_response.dart';
import 'models/whisper_dto.dart';

export 'models/_models.dart';
export 'whisper_audio_convert.dart';

/// Native request type
typedef WReqNative = Pointer<Utf8> Function(Pointer<Utf8> body);
typedef WFreeNative = Void Function(Pointer<Utf8> ptr);
typedef WFreeDart = void Function(Pointer<Utf8> ptr);

/// Entry point
class Whisper {
  /// [model] is required
  /// [modelDir] is path where downloaded model will be stored.
  /// Default to library directory
  const Whisper({required this.model, this.modelDir});

  /// model used for transcription
  final WhisperModel model;

  /// override of model storage path
  final String? modelDir;

  DynamicLibrary _openLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libwhisper.so');
    } else {
      return DynamicLibrary.process();
    }
  }

  Future<Map<String, dynamic>> _request({
    required WhisperRequestDto whisperRequest,
  }) async {
    return Isolate.run(() async {
      final DynamicLibrary lib = _openLib();
      final Pointer<Utf8> data =
          whisperRequest.toRequestString().toNativeUtf8();
      Pointer<Utf8> res = nullptr;

      try {
        res = lib.lookupFunction<WReqNative, WReqNative>('request').call(data);
        if (res == nullptr) {
          throw Exception('Native request() returned null');
        }

        final String resStr = res.toDartString();
        final Object decoded = json.decode(resStr);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Unexpected native response type');
        }
        return decoded;
      } finally {
        malloc.free(data);
        if (res != nullptr) {
          // Response is allocated by native malloc; free it via native.
          lib.lookupFunction<WFreeNative, WFreeDart>('free_response').call(res);
        }
      }
    });
  }

  /// Transcribe audio file to text
  Future<WhisperTranscribeResponse> transcribe({
    required TranscribeRequest transcribeRequest,
    required String modelPath,
  }) async {
    try {
      final Map<String, dynamic> result = await _request(
        whisperRequest: TranscribeRequestDto.fromTranscribeRequest(
          transcribeRequest,
          modelPath,
        ),
      );

      if (result['text'] == null) {
        throw Exception(result['message']);
      }
      return WhisperTranscribeResponse.fromJson(result);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  /// Get whisper version
  Future<String?> getVersion() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const VersionRequest(),
    );

    final WhisperVersionResponse response = WhisperVersionResponse.fromJson(
      result,
    );
    return response.message;
  }

  Future<void> abort() async {
    await _request(whisperRequest: const AbortRequest());
  }
}
