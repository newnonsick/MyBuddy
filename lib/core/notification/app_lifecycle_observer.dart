import 'package:flutter/widgets.dart';

import '../overlay/overlay_service.dart';
import 'notification_service.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver({
    NotificationService? notificationService,
    OverlayService? overlayService,
    this.onResume,
  }) : _notificationService = notificationService ?? NotificationService(),
       _overlayService = overlayService ?? OverlayService();

  final NotificationService _notificationService;
  final OverlayService _overlayService;
  final Future<void> Function()? onResume;

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setAppForegroundState(true);
    _overlayService.initialize();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    _overlayService.onAppLifecycleChanged(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _notificationService.setAppForegroundState(true);
        _notificationService.onAppOpened();
        onResume?.call();
        break;

      case AppLifecycleState.inactive:
        break;

      case AppLifecycleState.paused:
        _notificationService.setAppForegroundState(false);
        break;

      case AppLifecycleState.detached:
        _notificationService.setAppForegroundState(false);
        break;

      case AppLifecycleState.hidden:
        _notificationService.setAppForegroundState(false);
        break;
    }
  }
}
