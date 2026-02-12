import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OverlayUiMode { minimal, balanced, avatarLite }

extension OverlayUiModeX on OverlayUiMode {
  String get storageValue => name;

  String get label {
    switch (this) {
      case OverlayUiMode.minimal:
        return 'Minimal';
      case OverlayUiMode.balanced:
        return 'Balanced';
      case OverlayUiMode.avatarLite:
        return 'Avatar-lite';
    }
  }

  static OverlayUiMode fromStorage(String? value) {
    for (final mode in OverlayUiMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return OverlayUiMode.balanced;
  }
}

abstract final class OverlayPreferenceKeys {
  static const String autoOpenOnBackground =
      'mybuddy.overlay.auto_open_on_background.v1';
  static const String overlayTtsEnabled = 'mybuddy.overlay.tts_enabled.v1';
  static const String uiMode = 'mybuddy.overlay.ui_mode.v1';
  static const String customHeight = 'mybuddy.overlay.custom_height.v1';
}

class OverlayPreferences extends ChangeNotifier {
  bool _loaded = false;

  bool _autoOpenOnBackground = true;
  bool get autoOpenOnBackground => _autoOpenOnBackground;

  bool _overlayTtsEnabled = true;
  bool get overlayTtsEnabled => _overlayTtsEnabled;

  OverlayUiMode _mode = OverlayUiMode.balanced;
  OverlayUiMode get mode => _mode;

  int? _customHeight;
  int? get customHeight => _customHeight;

  Future<void> load() async {
    if (_loaded) return;

    final prefs = await SharedPreferences.getInstance();
    _autoOpenOnBackground =
        prefs.getBool(OverlayPreferenceKeys.autoOpenOnBackground) ?? true;
    _overlayTtsEnabled =
        prefs.getBool(OverlayPreferenceKeys.overlayTtsEnabled) ?? true;
    _mode = OverlayUiModeX.fromStorage(
      prefs.getString(OverlayPreferenceKeys.uiMode),
    );
    _customHeight = prefs.getInt(OverlayPreferenceKeys.customHeight);

    _loaded = true;
    notifyListeners();
  }

  Future<void> setAutoOpenOnBackground(bool value) async {
    if (value == _autoOpenOnBackground) return;
    _autoOpenOnBackground = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OverlayPreferenceKeys.autoOpenOnBackground, value);
  }

  Future<void> setOverlayTtsEnabled(bool value) async {
    if (value == _overlayTtsEnabled) return;
    _overlayTtsEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OverlayPreferenceKeys.overlayTtsEnabled, value);
  }

  Future<void> setMode(OverlayUiMode value) async {
    if (value == _mode) return;
    _mode = value;
    _customHeight = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(OverlayPreferenceKeys.uiMode, value.storageValue);
    await prefs.remove(OverlayPreferenceKeys.customHeight);
  }

  Future<void> setCustomHeight(int? height) async {
    if (height == _customHeight) return;
    _customHeight = height;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (height == null) {
      await prefs.remove(OverlayPreferenceKeys.customHeight);
    } else {
      await prefs.setInt(OverlayPreferenceKeys.customHeight, height);
    }
  }
}
