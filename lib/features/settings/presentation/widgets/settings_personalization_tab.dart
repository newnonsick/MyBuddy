import 'package:flutter/material.dart';

import 'llm_model_management.dart';
import 'settings_common.dart';
import 'stt_model_management.dart';

class SettingsPersonalizationTab extends StatelessWidget {
  const SettingsPersonalizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabTitle('Personalization'),
          SettingsSectionTitle('LLM model'),
          LlmModelManagement(),
          SizedBox(height: 16),
          SettingsSectionTitle('Speech-to-Text model'),
          SttModelManagement(),
        ],
      ),
    );
  }
}
