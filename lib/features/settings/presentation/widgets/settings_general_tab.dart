import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/overlay/overlay_preferences.dart';
import '../../../../core/stt/whisper_languages.dart';
import 'settings_common.dart';

class SettingsGeneralTab extends ConsumerWidget {
  const SettingsGeneralTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final stt = ref.watch(sttModelControllerProvider);
    final overlayService = ref.watch(overlayServiceProvider);
    final overlayPrefs = overlayService.preferences;
    final isAndroid = overlayService.isSupported;

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
          const SettingsSectionTitle('Overlay chat (Android)'),
          SettingsCard(
            items: [
              SettingsSwitchRow(
                title: 'Auto-open overlay in background',
                subtitle: isAndroid
                    ? 'Show chat overlay automatically when app goes to background.'
                    : 'Overlay is available on Android only.',
                value: overlayPrefs.autoOpenOnBackground,
                onChanged: isAndroid
                    ? overlayService.setAutoOpenOnBackground
                    : (_) async {},
              ),
              SettingsSwitchRow(
                title: 'Speak replies in overlay',
                subtitle: 'Enable text-to-speech for overlay responses.',
                value: overlayPrefs.overlayTtsEnabled,
                onChanged: overlayService.setOverlayTtsEnabled,
              ),
              SettingsDropdownRow(
                title: 'Overlay UI mode',
                subtitle: 'Choose Minimal, Balanced, or Avatar-lite.',
                value: overlayPrefs.mode.storageValue,
                items: OverlayUiMode.values
                    .map((mode) => mode.storageValue)
                    .toList(),
                itemLabelBuilder: (value) =>
                    OverlayUiModeX.fromStorage(value).label,
                onChanged: (value) async {
                  await overlayService.setMode(
                    OverlayUiModeX.fromStorage(value),
                  );
                },
              ),
              SettingsActionRow(
                title: 'Overlay permission',
                subtitle: !isAndroid
                    ? 'Not supported on this platform.'
                    : (overlayService.permissionGranted
                          ? 'Permission granted'
                          : 'Permission required to display overlay.'),
                actionText: 'Request',
                onAction: () => overlayService.requestPermission(),
              ),
              SettingsActionRow(
                title: 'Overlay status',
                subtitle: overlayService.overlayActive
                    ? 'Overlay is active'
                    : 'Overlay is closed',
                actionText: overlayService.overlayActive ? 'Close' : 'Open',
                onAction: () {
                  if (overlayService.overlayActive) {
                    overlayService.closeOverlay();
                    return;
                  }
                  overlayService.showOverlay();
                },
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
                items: WhisperLanguages.codes,
                itemLabelBuilder: WhisperLanguages.labelFor,
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
