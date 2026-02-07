import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/stt/stt_catalog_service.dart';
import '../core/stt/stt_model_descriptor.dart';
import '../core/stt/stt_selection_service.dart';
import '../core/stt/stt_store.dart';

enum SttCatalogState { idle, loading, ready, error }

class SttModelController extends ChangeNotifier {
  SttModelController({
    SttCatalogService? catalog,
    SttStore? store,
    SttSelectionService? selection,
  }) : _catalog = catalog ?? SttCatalogService(),
       _store = store ?? SttStore(),
       _selection = selection ?? SttSelectionService();

  final SttCatalogService _catalog;
  final SttStore _store;
  final SttSelectionService _selection;

  SttCatalogState _catalogState = SttCatalogState.idle;
  SttCatalogState get catalogState => _catalogState;

  String? _catalogError;
  String? get catalogError => _catalogError;

  List<RemoteSttModelDescriptor> _catalogItems =
      const <RemoteSttModelDescriptor>[];
  List<RemoteSttModelDescriptor> get catalogItems => _catalogItems;

  List<InstalledSttModel> _installed = const <InstalledSttModel>[];
  List<InstalledSttModel> get installedModels => _installed;

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  String? _lastUsedModelId;
  String? get lastUsedModelId => _lastUsedModelId;

  String? _pendingSelectionId;
  String? get pendingSelectionId => _pendingSelectionId;

  String _selectedLanguage = 'auto';
  String get selectedLanguage => _selectedLanguage;

  InstalledSttModel? get selectedInstalledModel {
    final id = _selectedModelId;
    if (id == null) return null;
    return _installed.cast<InstalledSttModel?>().firstWhere(
      (m) => m?.id == id,
      orElse: () => null,
    );
  }

  bool _downloading = false;
  bool get downloading => _downloading;

  SttDownloadProgress? _downloadProgress;
  SttDownloadProgress? get downloadProgress => _downloadProgress;

  String? _downloadError;
  String? get downloadError => _downloadError;

  CancelToken? _cancelToken;

  Future<void> loadLocalState() async {
    _installed = await _store.listInstalled();
    _selectedModelId = await _selection.loadSelectedModelId();
    _lastUsedModelId = await _selection.loadLastUsedModelId();
    _pendingSelectionId = _selectedModelId;
    _selectedLanguage = await _selection.loadSelectedLanguage();
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    _catalogState = SttCatalogState.loading;
    _catalogError = null;
    notifyListeners();

    try {
      _catalogItems = await _catalog.fetchCatalog();
      await _reconcileCatalogWithLocalFiles();
      _catalogState = SttCatalogState.ready;
    } catch (e) {
      _catalogError = '$e';
      _catalogState = SttCatalogState.error;
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
      } catch (_) {
        // Ignore registration failures
      }
    }
    await refreshInstalled();
  }

  Future<void> refreshInstalled() async {
    _installed = await _store.listInstalled();
    notifyListeners();
  }

  Future<void> startDownload(RemoteSttModelDescriptor remote) async {
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
        onProgress: _handleDownloadProgress,
      );
      await refreshInstalled();
    } on DioException catch (e) {
      _downloadError = CancelToken.isCancel(e) ? 'Download cancelled.' : '$e';
    } catch (e) {
      _downloadError = '$e';
    } finally {
      _cancelToken = null;
      _downloading = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  void _handleDownloadProgress(SttDownloadProgress progress) {
    _downloadProgress = progress;
    notifyListeners();
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

  Future<void> setSelectedLanguage(String lang) async {
    final next = lang.trim().isEmpty ? 'auto' : lang.trim();
    if (next == _selectedLanguage) return;

    _selectedLanguage = next;
    notifyListeners();

    await _selection.saveSelectedLanguage(next);
  }

  Future<void> deleteModel(InstalledSttModel model) async {
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
