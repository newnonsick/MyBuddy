import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';

import 'model_descriptor.dart';

class ModelCatalogService {
  ModelCatalogService({Dio? dio}) : _dio = dio ?? Dio();

  static const String defaultCatalogUrl =
      'https://raw.githubusercontent.com/newnonsick/MyBuddy-cfg/refs/heads/main/llm_models.json';

  final Dio _dio;

  Future<List<RemoteModelDescriptor>> fetchCatalog({String? url}) async {
    final u = (url == null || url.trim().isEmpty) ? defaultCatalogUrl : url;

    final resp = await _dio.get<Object?>(
      u,
      options: Options(responseType: ResponseType.json),
    );
    final raw = resp.data;
    debugPrint('Model catalog response: $raw');
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! List) {
      throw StateError('Catalog response is not a JSON list.');
    }

    final items = <RemoteModelDescriptor>[];
    for (final raw in data) {
      if (raw is Map) {
        final map = raw.cast<String, Object?>();
        final item = RemoteModelDescriptor.fromJson(map);
        if (item.id.trim().isEmpty) continue;
        if (item.fileName.trim().isEmpty) continue;
        if (item.downloadUrl.trim().isEmpty) continue;
        items.add(item);
      }
    }
    return items;
  }
}
