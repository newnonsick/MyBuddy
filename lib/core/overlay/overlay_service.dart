import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay_preferences.dart';

class OverlayService extends ChangeNotifier {
  factory OverlayService() => _instance;
  OverlayService._internal() {
    _preferences.addListener(_onPreferencesChanged);
  }

  static final OverlayService _instance = OverlayService._internal();

  final OverlayPreferences _preferences = OverlayPreferences();

  OverlayPreferences get preferences => _preferences;

  bool _initialized = false;
  bool _permissionGranted = false;
  bool _overlayActive = false;
  int _lifecycleTicket = 0;
  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;

  bool get isSupported => !kIsWeb && Platform.isAndroid;
  bool get permissionGranted => _permissionGranted;
  bool get overlayActive => _overlayActive;

  void _onPreferencesChanged() {
    notifyListeners();
  }

  Future<void> setAutoOpenOnBackground(bool value) async {
    await _preferences.setAutoOpenOnBackground(value);
  }

  Future<void> setOverlayTtsEnabled(bool value) async {
    await _preferences.setOverlayTtsEnabled(value);
    await syncOverlayConfig();
  }

  Future<void> setMode(OverlayUiMode value) async {
    await _preferences.setMode(value);
    await syncOverlayConfig();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    await _preferences.load();
    await _refreshRuntimeState();

    _initialized = true;
    notifyListeners();
  }

  Future<void> _refreshRuntimeState() async {
    if (!isSupported) return;

    try {
      _permissionGranted = await FlutterOverlayWindow.isPermissionGranted();
      _overlayActive = await FlutterOverlayWindow.isActive();
    } catch (_) {
      _permissionGranted = false;
      _overlayActive = false;
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;

    final granted = await FlutterOverlayWindow.requestPermission();
    _permissionGranted = granted ?? false;
    notifyListeners();
    return granted ?? false;
  }

  Future<void> showOverlay({OverlayUiMode? mode}) async {
    if (!isSupported) return;

    await _refreshRuntimeState();

    if (!_permissionGranted) {
      final granted = await requestPermission();
      if (!granted) return;
    }

    if (_overlayActive) {
      await _shareConfig();
      return;
    }

    final selectedMode = mode ?? _preferences.mode;
    final size = _sizeForMode(selectedMode);

    double screenH = 0;
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      if (dispatcher.displays.isNotEmpty) {
        final d = dispatcher.displays.first;
        screenH = d.size.height / d.devicePixelRatio;
      } else if (dispatcher.views.isNotEmpty) {
        final v = dispatcher.views.first;
        screenH = v.physicalSize.height / v.devicePixelRatio;
      }
    } catch (_) {}
    final startY = screenH > 100
        ? ((screenH - size.$2) / 2).clamp(0, screenH).round()
        : 100;

    await FlutterOverlayWindow.showOverlay(
      width: size.$1,
      height: size.$2,
      enableDrag: true,
      overlayTitle: 'MyBuddy Overlay',
      overlayContent: 'Chat with MyBuddy while using other apps',
      flag: OverlayFlag.focusPointer,
      alignment: OverlayAlignment.topLeft,
      positionGravity: PositionGravity.auto,
      startPosition: OverlayPosition(0, startY.toDouble()),
    );

    _overlayActive = true;
    notifyListeners();

    await _shareConfig();
  }

  Future<void> closeOverlay() async {
    if (!isSupported) return;

    await FlutterOverlayWindow.closeOverlay();
    _overlayActive = false;
    notifyListeners();
  }

  Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    if (!isSupported) return;

    final bool isForegrounding = 
        (_lastLifecycleState == AppLifecycleState.paused || 
         _lastLifecycleState == AppLifecycleState.hidden ||
         _lastLifecycleState == AppLifecycleState.detached) && 
        state == AppLifecycleState.inactive;

    _lastLifecycleState = state;

    final ticket = ++_lifecycleTicket;

    if (state == AppLifecycleState.resumed || isForegrounding) {
      try {
        await FlutterOverlayWindow.closeOverlay()
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Ignore when no overlay is currently attached or timed out.
      }
      _overlayActive = false;
      await _refreshRuntimeState();
      notifyListeners();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      await Future<void>.delayed(const Duration(milliseconds: 280));

      if (ticket != _lifecycleTicket) return;
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState == AppLifecycleState.resumed) return;

      await _refreshRuntimeState();
      if (_overlayActive) {
        await _shareConfig();
        return;
      }

      if (_preferences.autoOpenOnBackground) {
        await showOverlay();
      }
    }
  }

  Future<void> syncOverlayConfig() => _shareConfig();

  Future<void> _shareConfig() async {
    if (!isSupported) return;

    final size = _sizeForMode(_preferences.mode);
    if (_overlayActive) {
      try {
        await FlutterOverlayWindow.resizeOverlay(size.$1, size.$2, false);
      } catch (_) {
        // ignore resize failures and continue syncing config
      }
    }

    double screenW = 0;
    double screenH = 0;
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      if (dispatcher.displays.isNotEmpty) {
        final d = dispatcher.displays.first;
        screenW = d.size.width / d.devicePixelRatio;
        screenH = d.size.height / d.devicePixelRatio;
      } else if (dispatcher.views.isNotEmpty) {
        final v = dispatcher.views.first;
        screenW = v.physicalSize.width / v.devicePixelRatio;
        screenH = v.physicalSize.height / v.devicePixelRatio;
      }
    } catch (_) {}

    final payload = <String, Object>{
      'type': 'overlay_config',
      'mode': _preferences.mode.storageValue,
      'ttsEnabled': _preferences.overlayTtsEnabled,
      if (screenW > 0) 'screenWidth': screenW,
      if (screenH > 0) 'screenHeight': screenH,
    };

    await FlutterOverlayWindow.shareData(jsonEncode(payload));
  }

  (int, int) _sizeForMode(OverlayUiMode mode) {
    final custom = _preferences.customHeight;
    if (custom != null && custom >= 200) {
      return (WindowSize.matchParent, custom);
    }
    return (
      WindowSize.matchParent,
      _defaultHeightForMode(mode, _readScreenHeight()),
    );
  }

  static int _defaultHeightForMode(OverlayUiMode mode, double screenHeight) {
    final hasScreen = screenHeight > 100;
    final maxHeight = hasScreen ? (screenHeight - 24).round() : 980;

    switch (mode) {
      case OverlayUiMode.minimal:
        final target = hasScreen ? (screenHeight * 0.80).round() : 640;
        return target.clamp(480, maxHeight);
      case OverlayUiMode.avatarLite:
        final target = hasScreen ? (screenHeight * 0.95).round() : 920;
        return target.clamp(640, maxHeight);
      case OverlayUiMode.balanced:
        final target = hasScreen ? (screenHeight * 0.90).round() : 840;
        return target.clamp(600, maxHeight);
    }
  }

  double _readScreenHeight() {
    double screenH = 0;
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      if (dispatcher.displays.isNotEmpty) {
        final d = dispatcher.displays.first;
        screenH = d.size.height / d.devicePixelRatio;
      } else if (dispatcher.views.isNotEmpty) {
        final v = dispatcher.views.first;
        screenH = v.physicalSize.height / v.devicePixelRatio;
      }
    } catch (_) {
      screenH = 0;
    }
    return screenH;
  }
}
