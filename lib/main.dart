import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/my_app.dart';
import 'core/notification/app_lifecycle_observer.dart';
import 'core/notification/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.onAppOpened();

  runApp(
    ProviderScope(
      child: _AppWithLifecycle(
        notificationService: notificationService,
        child: const MyApp(),
      ),
    ),
  );
}

class _AppWithLifecycle extends StatefulWidget {
  const _AppWithLifecycle({
    required this.notificationService,
    required this.child,
  });

  final NotificationService notificationService;
  final Widget child;

  @override
  State<_AppWithLifecycle> createState() => _AppWithLifecycleState();
}

class _AppWithLifecycleState extends State<_AppWithLifecycle> {
  late final AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = AppLifecycleObserver(
      notificationService: widget.notificationService,
    )..initialize();
  }

  @override
  void dispose() {
    _lifecycleObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
