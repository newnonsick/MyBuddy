import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/model_controller.dart';
import '../../../../app/my_app.dart';
import '../../../../app/providers.dart';
import '../../../../core/llm/llm_service.dart';
import '../../../../core/memory/memory_service.dart';
import '../../../../core/overlay/overlay_app_proxy.dart';
import 'overlay_chat_page.dart';

final overlayMessageStreamProvider = Provider<Stream<dynamic>>((ref) {
  throw UnimplementedError('Must be overridden');
});

class OverlayHostApp extends StatefulWidget {
  const OverlayHostApp({super.key});

  @override
  State<OverlayHostApp> createState() => _OverlayHostAppState();
}

class _OverlayHostAppState extends State<OverlayHostApp> {
  late final OverlayAppProxy _proxy;
  late final StreamController<dynamic> _broadcastController;
  StreamSubscription<dynamic>? _rawSubscription;

  @override
  void initState() {
    super.initState();
    _broadcastController = StreamController<dynamic>.broadcast();

    _rawSubscription = FlutterOverlayWindow.overlayListener.listen(
      _broadcastController.add,
      onError: _broadcastController.addError,
    );

    _proxy = OverlayAppProxy(
      models: ModelController(),
      llm: LlmService.dummy(),
      memory: MemoryService(),
    );
    _proxy.startListening(_broadcastController.stream);
  }

  @override
  void dispose() {
    _proxy.disposeRelay();
    _rawSubscription?.cancel();
    _broadcastController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appControllerProvider.overrideWith((_) => _proxy),
        sttServiceProvider.overrideWithValue(OverlaySttService(_proxy)),
        overlayMessageStreamProvider.overrideWithValue(
          _broadcastController.stream,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: AppColors.colorScheme,
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
        home: const Scaffold(
          backgroundColor: Colors.transparent,
          body: OverlayChatPage(),
        ),
      ),
    );
  }
}
