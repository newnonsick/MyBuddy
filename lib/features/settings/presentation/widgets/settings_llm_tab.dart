import 'package:flutter/material.dart';

import 'llm_model_management.dart';
import 'settings_common.dart';

class SettingsLlmTab extends StatelessWidget {
  const SettingsLlmTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabTitle('LLM'),
          SettingsSectionTitle('Active model & library'),
          LlmModelManagement(),
        ],
      ),
    );
  }
}
