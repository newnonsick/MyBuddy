import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

@immutable
class LlmModelConfig {
  const LlmModelConfig({
    required this.type,
    required this.maxTokens,
    required this.tokenBuffer,
    required this.randomSeed,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.isThinking,
    required this.supportsFunctionCalls,
    required this.fileType
  });

  final String type;
  final int maxTokens;
  final int tokenBuffer;
  final int randomSeed;
  final double temperature;
  final int topK;
  final double? topP;
  final bool isThinking;
  final bool supportsFunctionCalls;
  final ModelFileType fileType;

  static LlmModelConfig fromJson(Map<String, Object?> json) {
    final raw = (json['fileType'] ?? '').toString().trim().toLowerCase();
    final modelFileType = (raw == 'bin' || raw == 'binary')
        ? ModelFileType.binary
        : ModelFileType.task;

    return LlmModelConfig(
      type: (json['type'] ?? '').toString(),
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
      tokenBuffer: (json['tokenBuffer'] as num?)?.toInt() ?? 3584,
      randomSeed: (json['randomSeed'] as num?)?.toInt() ?? 1,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.8,
      topK: (json['topK'] as num?)?.toInt() ?? 1,
      topP: (json['topP'] as num?)?.toDouble(),
      isThinking: (json['isThinking'] as bool?) ?? false,
      supportsFunctionCalls: (json['supportsFunctionCalls'] as bool?) ?? false,
      fileType: modelFileType,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'maxTokens': maxTokens,
      'tokenBuffer': tokenBuffer,
      'randomSeed': randomSeed,
      'temperature': temperature,
      'topK': topK,
      'topP': topP,
      'isThinking': isThinking,
      'supportsFunctionCalls': supportsFunctionCalls,
      'fileType': fileType == ModelFileType.binary ? 'binary' : 'task',
    };
  }

  ModelType toGemmaModelType() {
    final t = type.trim().toLowerCase();
    switch (t) {
      case 'qwen':
        return ModelType.qwen;
      case 'deepseek':
        return ModelType.deepSeek;
      case 'gemmait':
        return ModelType.gemmaIt;
      case 'llama':
        return ModelType.llama;
      case 'hammer':
        return ModelType.hammer;
      case 'functiongemma':
        return ModelType.functionGemma;
      case 'general':
        return ModelType.general;
      default:
        return ModelType.qwen;
    }
  }
}

@immutable
class RemoteModelDescriptor {
  const RemoteModelDescriptor({
    required this.id,
    required this.fileName,
    required this.downloadUrl,
    required this.approximateSize,
    required this.expectedMinBytes,
    required this.config,
  });

  final String id;
  final String fileName;
  final String downloadUrl;
  final String? approximateSize;
  final int? expectedMinBytes;
  final LlmModelConfig config;

  static RemoteModelDescriptor fromJson(Map<String, Object?> json) {
    return RemoteModelDescriptor(
      id: (json['id'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      approximateSize: json['approximateSize']?.toString(),
      expectedMinBytes: (json['expectedMinBytes'] as num?)?.toInt(),
      config: LlmModelConfig.fromJson(
        (json['config'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'approximateSize': approximateSize,
      'expectedMinBytes': expectedMinBytes,
      'config': config.toJson(),
    };
  }
}

@immutable
class InstalledModel {
  const InstalledModel({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.expectedMinBytes,
    required this.config,
    required this.downloadedBytes,
    required this.downloadedAtIso,
  });

  final String id;
  final String fileName;
  final String localPath;
  final int? expectedMinBytes;
  final LlmModelConfig config;
  final int downloadedBytes;
  final String downloadedAtIso;

  static InstalledModel fromJson(Map<String, Object?> json) {
    return InstalledModel(
      id: (json['id'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      expectedMinBytes: (json['expectedMinBytes'] as num?)?.toInt(),
      config: LlmModelConfig.fromJson(
        (json['config'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      downloadedAtIso: (json['downloadedAtIso'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'fileName': fileName,
      'localPath': localPath,
      'expectedMinBytes': expectedMinBytes,
      'config': config.toJson(),
      'downloadedBytes': downloadedBytes,
      'downloadedAtIso': downloadedAtIso,
    };
  }
}
