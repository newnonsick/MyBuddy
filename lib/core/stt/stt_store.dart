import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'stt_model_descriptor.dart';

@immutable
class SttDownloadProgress {
  const SttDownloadProgress({
    required this.modelId,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
  });

  final String modelId;
  final String phase; // bin | coreml | extract
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return receivedBytes / totalBytes;
  }

  int get percent => (fraction * 100).clamp(0, 100).round();
}

class SttStore {
  SttStore({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _installedFileName = 'installed_stt_models.json';

  Future<Directory> _modelsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, 'stt_models'));
  }

  Future<File> _installedRegistryFile() async {
    final dir = await _modelsDir();
    return File(p.join(dir.path, _installedFileName));
  }

  Future<String> resolveLocalPath(String fileName) async {
    final dir = await _modelsDir();
    return p.join(dir.path, fileName);
  }

  bool _isValidFile(File file, {required int? expectedMinBytes}) {
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return false;
      if (stat.size <= 0) return false;
      final minBytes = expectedMinBytes;
      if (minBytes != null && stat.size < minBytes) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<InstalledSttModel>> listInstalled() async {
    final f = await _installedRegistryFile();
    if (!await f.exists()) return const <InstalledSttModel>[];

    try {
      final text = await f.readAsString();
      final data = jsonDecode(text);
      if (data is! List) return const <InstalledSttModel>[];

      final out = <InstalledSttModel>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final item = InstalledSttModel.fromJson(raw.cast<String, Object?>());
        if (item.id.trim().isEmpty) continue;

        final file = File(item.localPath);
        if (!_isValidFile(file, expectedMinBytes: item.expectedMinBytes)) {
          continue;
        }

        final coreMlPath = item.coreMlFolderPath;
        if (coreMlPath != null) {
          final dir = Directory(coreMlPath);
          if (!dir.existsSync()) {
            // Keep the model installed even if CoreML is missing.
            out.add(
              InstalledSttModel(
                id: item.id,
                fileName: item.fileName,
                localPath: item.localPath,
                expectedMinBytes: item.expectedMinBytes,
                modelType: item.modelType,
                config: item.config,
                display: item.display,
                downloadedBytes: item.downloadedBytes,
                downloadedAtIso: item.downloadedAtIso,
                coreMlFolderPath: null,
              ),
            );
            continue;
          }
        }

        out.add(item);
      }

      return out;
    } catch (_) {
      return const <InstalledSttModel>[];
    }
  }

  Future<void> _writeInstalled(List<InstalledSttModel> models) async {
    final dir = await _modelsDir();
    await dir.create(recursive: true);

    final f = await _installedRegistryFile();
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(models.map((m) => m.toJson()).toList());
    await f.writeAsString(text);
  }

  Future<bool> isInstalled(RemoteSttModelDescriptor remote) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    if (!_isValidFile(file, expectedMinBytes: remote.expectedMinBytes)) {
      return false;
    }

    final installed = await listInstalled();
    return installed.any((m) => m.id == remote.id);
  }

  Future<bool> hasValidFile(RemoteSttModelDescriptor remote) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    return _isValidFile(file, expectedMinBytes: remote.expectedMinBytes);
  }

  Future<InstalledSttModel> ensureRegistered(
    RemoteSttModelDescriptor remote, {
    String? coreMlFolderPath,
  }) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    if (!_isValidFile(file, expectedMinBytes: remote.expectedMinBytes)) {
      throw StateError('STT model file missing or invalid.');
    }

    final stat = await file.stat();
    final installed = await listInstalled();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final next = InstalledSttModel(
      id: remote.id,
      fileName: remote.fileName,
      localPath: localPath,
      expectedMinBytes: remote.expectedMinBytes,
      modelType: remote.modelType,
      config: remote.config,
      display: remote.display,
      downloadedBytes: stat.size,
      downloadedAtIso: nowIso,
      coreMlFolderPath: coreMlFolderPath,
    );

    final updated = <InstalledSttModel>[
      ...installed.where((m) => m.id != remote.id),
      next,
    ];

    await _writeInstalled(updated);
    return next;
  }

  Future<void> _safeDelete(FileSystemEntity e) async {
    try {
      if (await e.exists()) {
        await e.delete(recursive: true);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<InstalledSttModel> download({
    required RemoteSttModelDescriptor remote,
    required void Function(SttDownloadProgress progress) onProgress,
    required CancelToken cancelToken,
  }) async {
    final dir = await _modelsDir();
    await dir.create(recursive: true);

    final modelPath = await resolveLocalPath(remote.fileName);
    final modelFile = File(modelPath);

    String? coreMlFolderPath;

    if (!_isValidFile(modelFile, expectedMinBytes: remote.expectedMinBytes)) {
      final tempPath = '$modelPath.partial';
      final tempFile = File(tempPath);
      await _safeDelete(tempFile);

      final stopwatch = Stopwatch()..start();
      int lastBytes = 0;
      int lastMs = 0;

      try {
        await _dio.download(
          remote.downloadUrl,
          tempPath,
          cancelToken: cancelToken,
          deleteOnError: true,
          options: Options(
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          onReceiveProgress: (received, total) {
            final elapsedMs = stopwatch.elapsedMilliseconds;
            final deltaBytes = received - lastBytes;
            final deltaMs = elapsedMs - lastMs;
            final speed = (deltaMs > 0)
                ? (deltaBytes / (deltaMs / 1000.0))
                : 0.0;

            lastBytes = received;
            lastMs = elapsedMs;

            onProgress(
              SttDownloadProgress(
                modelId: remote.id,
                phase: 'bin',
                receivedBytes: received,
                totalBytes: total,
                speedBytesPerSecond: speed,
              ),
            );
          },
        );

        if (!_isValidFile(
          tempFile,
          expectedMinBytes: remote.expectedMinBytes,
        )) {
          await _safeDelete(tempFile);
          throw StateError('Downloaded STT model failed verification.');
        }

        await _safeDelete(modelFile);
        await tempFile.rename(modelPath);
      } finally {
        stopwatch.stop();
        await _safeDelete(File('$modelPath.partial'));
      }
    }

    // Optional CoreML encoder: iOS/macOS only.
    final coreMl = remote.config.coreML;
    final shouldDownloadCoreMl =
        coreMl != null && (Platform.isIOS || Platform.isMacOS);

    if (shouldDownloadCoreMl) {
      final archivePath = p.join(dir.path, coreMl.archiveFileName);
      final archiveFile = File(archivePath);
      final tempZipPath = '$archivePath.partial';
      final tempZipFile = File(tempZipPath);

      final extractedDirPath = p.join(dir.path, coreMl.extractedFolderName);
      final extractedDir = Directory(extractedDirPath);

      if (!extractedDir.existsSync()) {
        await _safeDelete(tempZipFile);

        final stopwatch = Stopwatch()..start();
        int lastBytes = 0;
        int lastMs = 0;

        try {
          await _dio.download(
            coreMl.downloadUrl,
            tempZipPath,
            cancelToken: cancelToken,
            deleteOnError: true,
            options: Options(
              followRedirects: true,
              validateStatus: (status) => status != null && status < 400,
            ),
            onReceiveProgress: (received, total) {
              final elapsedMs = stopwatch.elapsedMilliseconds;
              final deltaBytes = received - lastBytes;
              final deltaMs = elapsedMs - lastMs;
              final speed = (deltaMs > 0)
                  ? (deltaBytes / (deltaMs / 1000.0))
                  : 0.0;

              lastBytes = received;
              lastMs = elapsedMs;

              onProgress(
                SttDownloadProgress(
                  modelId: remote.id,
                  phase: 'coreml',
                  receivedBytes: received,
                  totalBytes: total,
                  speedBytesPerSecond: speed,
                ),
              );
            },
          );

          final minZipBytes = coreMl.expectedMinBytes;
          if (!_isValidFile(tempZipFile, expectedMinBytes: minZipBytes)) {
            await _safeDelete(tempZipFile);
            throw StateError('Downloaded CoreML archive failed verification.');
          }

          await _safeDelete(archiveFile);
          await tempZipFile.rename(archivePath);

          onProgress(
            SttDownloadProgress(
              modelId: remote.id,
              phase: 'extract',
              receivedBytes: 0,
              totalBytes: 0,
              speedBytesPerSecond: 0,
            ),
          );

          await compute(_extractZipInBackground, {
            'zipPath': archivePath,
            'destDir': dir.path,
          });

          if (!extractedDir.existsSync()) {
            throw StateError(
              'CoreML extraction complete, but ${coreMl.extractedFolderName} was not found.',
            );
          }

          coreMlFolderPath = extractedDir.path;
        } finally {
          stopwatch.stop();
          await _safeDelete(tempZipFile);
          await _safeDelete(archiveFile);
        }
      } else {
        coreMlFolderPath = extractedDir.path;
      }
    }

    return ensureRegistered(remote, coreMlFolderPath: coreMlFolderPath);
  }

  static Future<void> _extractZipInBackground(Map<String, String> args) async {
    final zipPath = args['zipPath'];
    final destDir = args['destDir'];
    if (zipPath == null || destDir == null) {
      throw ArgumentError('zipPath and destDir are required');
    }

    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      throw StateError('Zip file does not exist: $zipPath');
    }

    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      final outPath = p.join(destDir, filename);

      if (file.isFile) {
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
  }

  Future<void> delete(InstalledSttModel model) async {
    final file = File(model.localPath);
    await _safeDelete(file);

    final coreMl = model.coreMlFolderPath;
    if (coreMl != null) {
      await _safeDelete(Directory(coreMl));
    }

    final current = await listInstalled();
    final updated = current.where((m) => m.id != model.id).toList();
    await _writeInstalled(updated);
  }
}
