import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';

import 'stt_model_descriptor.dart';

class SttCatalogService {
  SttCatalogService({Dio? dio}) : _dio = dio ?? Dio();

  static const String defaultCatalogUrl = String.fromEnvironment(
    'STT_CATALOG_URL',
    defaultValue:
        'https://raw.githubusercontent.com/newnonsick/MyBuddy-cfg/main/stt_models.json',
  );

  final Dio _dio;

  Future<List<RemoteSttModelDescriptor>> fetchCatalog({String? url}) async {
    final u = (url == null || url.trim().isEmpty) ? defaultCatalogUrl : url;

    final resp = await _dio.get<Object?>(
      u,
      options: Options(responseType: ResponseType.json),
    );
    final raw = resp.data;
    debugPrint('STT catalog response: $raw');
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! List) {
      throw StateError('STT catalog response is not a JSON list.');
    }

    final items = <RemoteSttModelDescriptor>[];
    for (final itemRaw in data) {
      if (itemRaw is! Map) continue;
      final item = RemoteSttModelDescriptor.fromJson(
        itemRaw.cast<String, Object?>(),
      );
      if (item.id.trim().isEmpty) continue;
      if (item.fileName.trim().isEmpty) continue;
      if (item.downloadUrl.trim().isEmpty) continue;
      items.add(item);
    }

    return items;
  }
}
