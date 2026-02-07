import 'package:flutter/material.dart';

import '../../../../core/notification/notification_service.dart';
import 'settings_common.dart';

class SettingsNotificationsTab extends StatelessWidget {
  const SettingsNotificationsTab({
    super.key,
    required this.notificationService,
  });

  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsTabTitle('Notifications'),
          SettingsCard(
            items: [
              SettingsSwitchRow(
                title: 'Daily reminders',
                subtitle: 'Friendly reminders to chat with your buddy',
                value: notificationService.isDailyReminderEnabled,
                onChanged: notificationService.setDailyReminderEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
