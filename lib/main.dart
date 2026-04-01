import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_controller.dart';
import 'app/my_app.dart';
import 'app/providers.dart';
import 'core/notification/app_lifecycle_observer.dart';
import 'core/notification/notification_service.dart';
import 'core/overlay/overlay_chat_relay.dart';
import 'core/overlay/overlay_service.dart';
import 'features/overlay/presentation/pages/overlay_host_app.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: OverlayHostApp()));
}

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

class _AppWithLifecycle extends ConsumerStatefulWidget {
  const _AppWithLifecycle({
    required this.notificationService,
    required this.child,
  });

  final NotificationService notificationService;
  final Widget child;

  @override
  ConsumerState<_AppWithLifecycle> createState() => _AppWithLifecycleState();
}

class _AppWithLifecycleState extends ConsumerState<_AppWithLifecycle> {
  late final AppLifecycleObserver _lifecycleObserver;
  final OverlayService _overlayService = OverlayService();
  OverlayChatRelay? _chatRelay;

  @override
  void initState() {
    super.initState();
    unawaited(_overlayService.initialize());
    _lifecycleObserver = AppLifecycleObserver(
      notificationService: widget.notificationService,
      overlayService: _overlayService,
      onResume: _onAppResumed,
    )..initialize();
    final appController = ref.read(appControllerProvider);
    unawaited(_startAppController(appController));
    _chatRelay = OverlayChatRelay(
      appController: appController,
      sttService: ref.read(sttServiceProvider),
    )..start();
  }

  Future<void> _startAppController(AppController appController) async {
    try {
      await appController.startup();
    } catch (e, st) {
      debugPrint('App startup failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _chatRelay?.dispose();
    _lifecycleObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _onAppResumed() async {
    final models = ref.read(modelControllerProvider);
    final stt = ref.read(sttModelControllerProvider);
    final app = ref.read(appControllerProvider);

    final previousModelId = models.selectedModelId;

    await models.loadLocalState();
    await stt.loadLocalState();

    final newModelId = models.selectedModelId;
    if (newModelId != null &&
        newModelId != previousModelId &&
        app.llmInstalled) {
      await app.activateSelectedModel();
    }
  }
}
