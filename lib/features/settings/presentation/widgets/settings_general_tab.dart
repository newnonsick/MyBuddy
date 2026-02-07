import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import 'settings_common.dart';

class SettingsGeneralTab extends ConsumerWidget {
  const SettingsGeneralTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final stt = ref.watch(sttModelControllerProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsTabTitle('General'),
          SettingsCard(
            items: [
              SettingsSwitchRow(
                title: 'Hide chat log',
                subtitle: 'Hide messages from the screen',
                value: app.hideChatLog,
                onChanged: app.setHideChatLog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SettingsSectionTitle('Spoken language'),
          SettingsCard(
            items: [
              SettingsDropdownRow(
                title: 'Spoken language',
                subtitle:
                    'Select the input language for speech recognition (or auto).',
                value: stt.selectedLanguage,
                items: const <String>[
                  'auto',
                  'en',
                  'ko',
                  'ja',
                  'zh',
                  'fr',
                  'de',
                  'es',
                  'it',
                  'pt',
                  'ru',
                  'ar',
                  'hi',
                ],
                onChanged: (v) => stt.setSelectedLanguage(v),
              ),
              SettingsActionRow(
                title: 'Speech-to-Text model',
                subtitle: stt.selectedInstalledModel == null
                    ? 'No model selected'
                    : (stt.selectedInstalledModel!.display.name.isNotEmpty
                          ? stt.selectedInstalledModel!.display.name
                          : stt.selectedInstalledModel!.id),
                actionText: 'Manage',
                onAction: () => DefaultTabController.of(context).animateTo(3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
