import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_descriptor.dart';

@immutable
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.modelId,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
  });

  final String modelId;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return receivedBytes / totalBytes;
  }

  int get percent => (fraction * 100).clamp(0, 100).round();
}

class ModelStore {
  ModelStore({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _installedFileName = 'installed_models.json';

  Future<Directory> _modelsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, 'models'));
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

  Future<List<InstalledModel>> listInstalled() async {
    final f = await _installedRegistryFile();
    if (!await f.exists()) return const <InstalledModel>[];

    try {
      final text = await f.readAsString();
      final data = jsonDecode(text);
      if (data is! List) return const <InstalledModel>[];

      final out = <InstalledModel>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final item = InstalledModel.fromJson(raw.cast<String, Object?>());
        if (item.id.trim().isEmpty) continue;

        final file = File(item.localPath);
        if (!_isValidFile(file, expectedMinBytes: item.expectedMinBytes)) {
          continue;
        }
        out.add(item);
      }
      return out;
    } catch (_) {
      return const <InstalledModel>[];
    }
  }

  Future<void> _writeInstalled(List<InstalledModel> models) async {
    final dir = await _modelsDir();
    await dir.create(recursive: true);

    final f = await _installedRegistryFile();
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(models.map((m) => m.toJson()).toList());
    await f.writeAsString(text);
  }

  Future<InstalledModel?> getInstalledById(String id) async {
    final installed = await listInstalled();
    for (final m in installed) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<bool> isInstalled(RemoteModelDescriptor remote) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    if (!_isValidFile(file, expectedMinBytes: remote.expectedMinBytes)) {
      return false;
    }

    final installed = await listInstalled();
    return installed.any((m) => m.id == remote.id);
  }

  Future<bool> hasValidFile(RemoteModelDescriptor remote) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    return _isValidFile(file, expectedMinBytes: remote.expectedMinBytes);
  }

  Future<InstalledModel> ensureRegistered(RemoteModelDescriptor remote) async {
    final localPath = await resolveLocalPath(remote.fileName);
    final file = File(localPath);
    if (!_isValidFile(file, expectedMinBytes: remote.expectedMinBytes)) {
      throw StateError('Model file missing or invalid.');
    }

    final stat = await file.stat();
    final installed = await listInstalled();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final next = InstalledModel(
      id: remote.id,
      fileName: remote.fileName,
      localPath: localPath,
      expectedMinBytes: remote.expectedMinBytes,
      config: remote.config,
      downloadedBytes: stat.size,
      downloadedAtIso: nowIso,
    );

    final updated = <InstalledModel>[
      ...installed.where((m) => m.id != remote.id),
      next,
    ];
    await _writeInstalled(updated);
    return next;
  }

  Future<InstalledModel> download({
    required RemoteModelDescriptor remote,
    required void Function(ModelDownloadProgress progress) onProgress,
    required CancelToken cancelToken,
  }) async {
    final dir = await _modelsDir();
    await dir.create(recursive: true);

    final finalPath = await resolveLocalPath(remote.fileName);
    final finalFile = File(finalPath);

    if (_isValidFile(finalFile, expectedMinBytes: remote.expectedMinBytes)) {
      return ensureRegistered(remote);
    }

    final tempPath = '$finalPath.partial';
    final tempFile = File(tempPath);

    Future<void> safeDelete(FileSystemEntity e) async {
      try {
        if (await e.exists()) {
          await e.delete(recursive: true);
        }
      } catch (_) {
        // ignore
      }
    }

    await safeDelete(tempFile);

    final stopwatch = Stopwatch()..start();
    int lastBytes = 0;
    int lastMs = 0;

    try {
      await _dio.download(
        remote.downloadUrl,
        tempPath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final elapsedMs = stopwatch.elapsedMilliseconds;
          final deltaBytes = received - lastBytes;
          final deltaMs = elapsedMs - lastMs;
          final speed = (deltaMs > 0) ? (deltaBytes / (deltaMs / 1000.0)) : 0.0;

          lastBytes = received;
          lastMs = elapsedMs;

          onProgress(
            ModelDownloadProgress(
              modelId: remote.id,
              receivedBytes: received,
              totalBytes: total,
              speedBytesPerSecond: speed,
            ),
          );
        },
      );

      if (!_isValidFile(tempFile, expectedMinBytes: remote.expectedMinBytes)) {
        await safeDelete(tempFile);
        throw StateError('Downloaded model failed verification.');
      }

      await safeDelete(finalFile);
      await tempFile.rename(finalPath);

      return ensureRegistered(remote);
    } finally {
      stopwatch.stop();
      await safeDelete(tempFile);
    }
  }

  Future<void> delete(InstalledModel model) async {
    final file = File(model.localPath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ignore
    }
    
    final current = await listInstalled();
    final updated = current.where((m) => m.id != model.id).toList();
    await _writeInstalled(updated);
  }
}
