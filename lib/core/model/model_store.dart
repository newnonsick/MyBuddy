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
    final safeFileName = _sanitizeFileName(fileName);
    return p.join(dir.path, safeFileName);
  }

  String _sanitizeFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      throw StateError('Model file name is empty.');
    }

    if (RegExp(r'[\x00-\x1F]').hasMatch(trimmed)) {
      throw StateError('Model file name contains invalid characters.');
    }

    final normalized = trimmed.replaceAll('\\', '/');
    if (normalized.contains('/')) {
      throw StateError('Model file name must not contain path separators.');
    }

    if (p.isAbsolute(trimmed) || trimmed == '.' || trimmed == '..') {
      throw StateError('Model file name must be a relative file name.');
    }

    final base = p.basename(trimmed);
    if (base != trimmed) {
      throw StateError('Model file name is invalid.');
    }

    return base;
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

  bool _isGoogleDriveUrl(String url) {
    return url.contains('drive.google.com') ||
        url.contains('docs.google.com') ||
        url.contains('drive.usercontent.google.com');
  }

  String? _extractGoogleDriveFileId(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.queryParameters.containsKey('id')) {
      return uri.queryParameters['id'];
    }
    final regExp = RegExp(r'/d/([a-zA-Z0-9_-]+)');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  Map<String, String>? _parseGoogleDriveForm(String htmlContent) {
    final actionRegex = RegExp(r'<form[^>]*action="([^"]+)"');
    final actionMatch = actionRegex.firstMatch(htmlContent);
    if (actionMatch == null) return null;

    final result = <String, String>{'action': actionMatch.group(1)!};

    final inputRegex = RegExp(
      r'<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"',
    );
    for (final match in inputRegex.allMatches(htmlContent)) {
      final name = match.group(1);
      final value = match.group(2);
      if (name != null && value != null) {
        result[name] = value;
      }
    }

    final altInputRegex = RegExp(
      r'<input[^>]*value="([^"]*)"[^>]*name="([^"]+)"',
    );
    for (final match in altInputRegex.allMatches(htmlContent)) {
      final value = match.group(1);
      final name = match.group(2);
      if (name != null && value != null && !result.containsKey(name)) {
        result[name] = value;
      }
    }

    return result;
  }

  String? _buildGoogleDriveDownloadUrl(Map<String, String> formParams) {
    final action = formParams['action'];
    if (action == null) return null;

    final queryParams = <String, String>{};

    for (final entry in formParams.entries) {
      if (entry.key != 'action' && entry.value.isNotEmpty) {
        queryParams[entry.key] = entry.value;
      }
    }

    if (queryParams.isEmpty) return null;

    final uri = Uri.parse(action).replace(queryParameters: queryParams);
    return uri.toString();
  }

  Future<String> _resolveGoogleDriveUrl(
    String originalUrl,
    CancelToken cancelToken,
  ) async {
    final fileId = _extractGoogleDriveFileId(originalUrl);
    if (fileId == null) {
      return originalUrl;
    }

    final baseUrl =
        'https://drive.usercontent.google.com/uc?export=download&id=$fileId';

    final response = await _dio.get<dynamic>(
      baseUrl,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        responseType: ResponseType.plain,
      ),
    );

    if (response.data is String) {
      final htmlContent = response.data as String;
      final formParams = _parseGoogleDriveForm(htmlContent);

      if (formParams != null) {
        formParams['id'] ??= fileId;

        final downloadUrl = _buildGoogleDriveDownloadUrl(formParams);
        if (downloadUrl != null) {
          return downloadUrl;
        }
      }
    }

    final cookies = response.headers['set-cookie'];
    if (cookies != null) {
      for (final cookie in cookies) {
        if (cookie.contains('download_warning')) {
          final tokenMatch = RegExp(
            r'download_warning[^=]*=([^;]+)',
          ).firstMatch(cookie);
          if (tokenMatch != null) {
            final confirmToken = tokenMatch.group(1);
            return '$baseUrl&confirm=$confirmToken';
          }
        }
      }
    }

    return 'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t';
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
      String downloadUrl = remote.downloadUrl;
      if (_isGoogleDriveUrl(downloadUrl)) {
        downloadUrl = await _resolveGoogleDriveUrl(downloadUrl, cancelToken);
      }

      await _dio.download(
        downloadUrl,
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
