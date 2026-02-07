import 'package:flutter/material.dart';

import 'settings_common.dart';
import 'stt_model_management.dart';

class SettingsSttTab extends StatelessWidget {
  const SettingsSttTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabTitle('Speech-to-Text'),
          SettingsSectionTitle('Model'),
          SttModelManagement(),
        ],
      ),
    );
  }
}
