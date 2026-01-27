import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/model/model_catalog_service.dart';
import '../core/model/model_descriptor.dart';
import '../core/model/model_selection_service.dart';
import '../core/model/model_store.dart';

enum CatalogState { idle, loading, ready, error }

class ModelController extends ChangeNotifier {
  ModelController({
    ModelCatalogService? catalog,
    ModelStore? store,
    ModelSelectionService? selection,
  }) : _catalog = catalog ?? ModelCatalogService(),
       _store = store ?? ModelStore(),
       _selection = selection ?? ModelSelectionService();

  final ModelCatalogService _catalog;
  final ModelStore _store;
  final ModelSelectionService _selection;

  CatalogState _catalogState = CatalogState.idle;
  CatalogState get catalogState => _catalogState;

  String? _catalogError;
  String? get catalogError => _catalogError;

  List<RemoteModelDescriptor> _catalogItems = const <RemoteModelDescriptor>[];
  List<RemoteModelDescriptor> get catalogItems => _catalogItems;

  List<InstalledModel> _installed = const <InstalledModel>[];
  List<InstalledModel> get installedModels => _installed;

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  String? _lastUsedModelId;
  String? get lastUsedModelId => _lastUsedModelId;

  String? _pendingSelectionId;
  String? get pendingSelectionId => _pendingSelectionId;

  InstalledModel? get selectedInstalledModel {
    final id = _selectedModelId;
    if (id == null) return null;
    for (final m in _installed) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool _downloading = false;
  bool get downloading => _downloading;

  ModelDownloadProgress? _downloadProgress;
  ModelDownloadProgress? get downloadProgress => _downloadProgress;

  String? _downloadError;
  String? get downloadError => _downloadError;

  CancelToken? _cancelToken;

  Future<void> loadLocalState() async {
    _installed = await _store.listInstalled();
    _selectedModelId = await _selection.loadSelectedModelId();
    _lastUsedModelId = await _selection.loadLastUsedModelId();
    _pendingSelectionId = _selectedModelId;
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    _catalogState = CatalogState.loading;
    _catalogError = null;
    notifyListeners();

    try {
      _catalogItems = await _catalog.fetchCatalog();
      await _reconcileCatalogWithLocalFiles();
      _catalogState = CatalogState.ready;
    } catch (e) {
      _catalogError = '$e';
      _catalogState = CatalogState.error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _reconcileCatalogWithLocalFiles() async {
    for (final remote in _catalogItems) {
      final hasFile = await _store.hasValidFile(remote);
      if (!hasFile) continue;
      try {
        await _store.ensureRegistered(remote);
      } catch (_) {}
    }
    await refreshInstalled();
  }

  Future<void> refreshInstalled() async {
    _installed = await _store.listInstalled();
    notifyListeners();
  }

  Future<bool> isInstalled(RemoteModelDescriptor remote) async {
    return _store.isInstalled(remote);
  }

  Future<void> startDownload(RemoteModelDescriptor remote) async {
    if (_downloading) return;

    _downloading = true;
    _downloadProgress = null;
    _downloadError = null;
    notifyListeners();

    final token = CancelToken();
    _cancelToken = token;

    try {
      await _store.download(
        remote: remote,
        cancelToken: token,
        onProgress: (p) {
          _downloadProgress = p;
          notifyListeners();
        },
      );
      await refreshInstalled();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        _downloadError = 'Download cancelled.';
      } else {
        _downloadError = '$e';
      }
    } finally {
      _cancelToken = null;
      _downloading = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  Future<void> cancelDownload() async {
    _cancelToken?.cancel('User cancelled');
  }

  void setPendingSelection(String? id) {
    _pendingSelectionId = id;
    notifyListeners();
  }

  Future<void> commitSelection() async {
    final id = _pendingSelectionId;
    await _selection.saveSelectedModelId(id);
    _selectedModelId = id;
    notifyListeners();
  }

  Future<void> markLastUsedSelected() async {
    final id = _selectedModelId;
    await _selection.saveLastUsedModelId(id);
    _lastUsedModelId = id;
    notifyListeners();
  }

  Future<void> deleteModel(InstalledModel model) async {
    await _store.delete(model);
    if (_selectedModelId == model.id) {
      _selectedModelId = null;
      await _selection.saveSelectedModelId(null);
    }
    if (_pendingSelectionId == model.id) {
      _pendingSelectionId = null;
    }
    await refreshInstalled();
  }
}
