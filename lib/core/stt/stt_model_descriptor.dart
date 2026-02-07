import 'package:flutter/foundation.dart';

@immutable
class SttCoreMlConfig {
  const SttCoreMlConfig({
    required this.downloadUrl,
    required this.archiveFileName,
    required this.extractedFolderName,
    required this.approximateSize,
    required this.expectedMinBytes,
  });

  final String downloadUrl;
  final String archiveFileName;
  final String extractedFolderName;
  final String? approximateSize;
  final int? expectedMinBytes;

  static SttCoreMlConfig fromJson(Map<String, Object?> json) {
    return SttCoreMlConfig(
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      archiveFileName: (json['archiveFileName'] ?? '').toString(),
      extractedFolderName: (json['extractedFolderName'] ?? '').toString(),
      approximateSize: json['approximateSize']?.toString(),
      expectedMinBytes: (json['expectedMinBytes'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'downloadUrl': downloadUrl,
      'archiveFileName': archiveFileName,
      'extractedFolderName': extractedFolderName,
      'approximateSize': approximateSize,
      'expectedMinBytes': expectedMinBytes,
    };
  }
}

@immutable
class SttModelConfig {
  const SttModelConfig({
    required this.variant,
    required this.quantization,
    required this.coreML,
  });

  final String variant;
  final String quantization;
  final SttCoreMlConfig? coreML;

  static SttModelConfig fromJson(Map<String, Object?> json) {
    final coreMlRaw = json['coreML'];
    return SttModelConfig(
      variant: (json['variant'] ?? '').toString(),
      quantization: (json['quantization'] ?? '').toString(),
      coreML: (coreMlRaw is Map)
          ? SttCoreMlConfig.fromJson(coreMlRaw.cast<String, Object?>())
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'variant': variant,
      'quantization': quantization,
      'coreML': coreML?.toJson(),
    };
  }
}

@immutable
class SttModelDisplay {
  const SttModelDisplay({required this.name, required this.description});

  final String name;
  final String description;

  static SttModelDisplay fromJson(Map<String, Object?> json) {
    return SttModelDisplay(
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'name': name, 'description': description};
  }
}

@immutable
class RemoteSttModelDescriptor {
  const RemoteSttModelDescriptor({
    required this.id,
    required this.fileName,
    required this.downloadUrl,
    required this.approximateSize,
    required this.expectedMinBytes,
    required this.modelType,
    required this.config,
    required this.display,
  });

  final String id;
  final String fileName;
  final String downloadUrl;
  final String? approximateSize;
  final int? expectedMinBytes;
  final String modelType;
  final SttModelConfig config;
  final SttModelDisplay display;

  static RemoteSttModelDescriptor fromJson(Map<String, Object?> json) {
    return RemoteSttModelDescriptor(
      id: (json['id'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      approximateSize: json['approximateSize']?.toString(),
      expectedMinBytes: (json['expectedMinBytes'] as num?)?.toInt(),
      modelType: (json['modelType'] ?? '').toString(),
      config: SttModelConfig.fromJson(
        (json['config'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      display: SttModelDisplay.fromJson(
        (json['display'] as Map?)?.cast<String, Object?>() ??
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
      'modelType': modelType,
      'config': config.toJson(),
      'display': display.toJson(),
    };
  }
}

@immutable
class InstalledSttModel {
  const InstalledSttModel({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.expectedMinBytes,
    required this.modelType,
    required this.config,
    required this.display,
    required this.downloadedBytes,
    required this.downloadedAtIso,
    required this.coreMlFolderPath,
  });

  final String id;
  final String fileName;
  final String localPath;
  final int? expectedMinBytes;
  final String modelType;
  final SttModelConfig config;
  final SttModelDisplay display;
  final int downloadedBytes;
  final String downloadedAtIso;

  /// Full path to the extracted `.mlmodelc` directory if present.
  final String? coreMlFolderPath;

  static InstalledSttModel fromJson(Map<String, Object?> json) {
    return InstalledSttModel(
      id: (json['id'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      expectedMinBytes: (json['expectedMinBytes'] as num?)?.toInt(),
      modelType: (json['modelType'] ?? '').toString(),
      config: SttModelConfig.fromJson(
        (json['config'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      display: SttModelDisplay.fromJson(
        (json['display'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      downloadedAtIso: (json['downloadedAtIso'] ?? '').toString(),
      coreMlFolderPath:
          (json['coreMlFolderPath'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['coreMlFolderPath'] as String?),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'fileName': fileName,
      'localPath': localPath,
      'expectedMinBytes': expectedMinBytes,
      'modelType': modelType,
      'config': config.toJson(),
      'display': display.toJson(),
      'downloadedBytes': downloadedBytes,
      'downloadedAtIso': downloadedAtIso,
      'coreMlFolderPath': coreMlFolderPath,
    };
  }
}
