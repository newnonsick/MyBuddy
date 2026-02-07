import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/notification/notification_service.dart';
import '../widgets/settings_general_tab.dart';
import '../widgets/settings_llm_tab.dart';
import '../widgets/settings_notifications_tab.dart';
import '../widgets/settings_shell.dart';
import '../widgets/settings_stt_tab.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final models = ref.read(modelControllerProvider);
      await models.loadLocalState();
      await models.refreshInstalled();
      await models.refreshCatalog();

      final stt = ref.read(sttModelControllerProvider);
      await stt.loadLocalState();
      await stt.refreshInstalled();
      await stt.refreshCatalog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _notificationService,
          builder: (context, _) {
            return DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const SettingsHeader(),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SettingsTabStrip(),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        const SettingsGeneralTab(),
                        SettingsNotificationsTab(
                          notificationService: _notificationService,
                        ),
                        const SettingsLlmTab(),
                        const SettingsSttTab(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
