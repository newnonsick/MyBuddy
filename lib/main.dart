import 'package:flutter/material.dart';

import 'package:mybuddy/app/my_app.dart';
import 'package:mybuddy/core/notification/notification_service.dart';
import 'package:mybuddy/core/notification/app_lifecycle_observer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationService = NotificationService();
  await notificationService.initialize();

  await notificationService.onAppOpened();

  final lifecycleObserver = AppLifecycleObserver(
    notificationService: notificationService,
  );
  lifecycleObserver.initialize();

  runApp(const MyApp());
}
