import 'package:flutter/widgets.dart';
import 'package:mybuddy/core/notification/notification_service.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  final NotificationService _notificationService;

  AppLifecycleObserver({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService();

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setAppForegroundState(true);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _notificationService.setAppForegroundState(true);
        _notificationService.onAppOpened();
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
