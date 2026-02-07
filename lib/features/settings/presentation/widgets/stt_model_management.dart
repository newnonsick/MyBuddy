import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/stt_model_controller.dart';
import '../../../../core/stt/stt_model_descriptor.dart';
import '../../../../core/stt/stt_store.dart';
import '../../../../core/stt/whisper_languages.dart';
import '../../../../core/utils/format_bytes.dart';
import '../../../../shared/widgets/glass/glass.dart';

class SttModelManagement extends ConsumerStatefulWidget {
  const SttModelManagement({super.key});

  @override
  ConsumerState<SttModelManagement> createState() => _SttModelManagementState();
}

class _SttModelManagementState extends ConsumerState<SttModelManagement> {
  @override
  Widget build(BuildContext context) {
    final stt = ref.watch(sttModelControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActiveSttModelCard(context, stt),
        const SizedBox(height: 12),
        _buildSttModelLibrary(context, stt),
      ],
    );
  }

  Widget _buildActiveSttModelCard(
    BuildContext context,
    SttModelController stt,
  ) {
    final installed = stt.installedModels;
    final pendingId = stt.pendingSelectionId;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (installed.isEmpty) ...[
            Icon(
              Icons.mic_off_rounded,
              size: 44,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              'No STT Models Downloaded',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Download a Speech-to-Text model below to enable voice input.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ] else ...[
            ...installed.map((m) {
              final isActive = m.id == stt.selectedModelId;
              final isSelected = m.id == pendingId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isActive
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.2)
                      : (isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => stt.setPendingSelection(m.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? Theme.of(context).colorScheme.primary
                                    : (isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.white.withValues(
                                              alpha: 0.3,
                                            )),
                                width: 2,
                              ),
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ),
                            child: isActive
                                ? const Center(
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  )
                                : (isSelected
                                      ? Center(
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                        )
                                      : null),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      m.display.name.isNotEmpty
                                          ? m.display.name
                                          : m.id,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Whisper • ${m.config.variant} • ${m.config.quantization}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                ),
                                if (m.coreMlFolderPath != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'CoreML encoder installed',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_rounded,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.6),
                            ),
                            onPressed: () => _confirmDeleteStt(context, m),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(child: _buildSttLanguagePicker(context, stt)),
                const SizedBox(width: 12),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: pendingId == null
                        ? null
                        : () async {
                            await stt.commitSelection();
                            await stt.markLastUsedSelected();
                          },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Set Active',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSttLanguagePicker(BuildContext context, SttModelController stt) {
    final langs = WhisperLanguages.codes;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.language_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: WhisperLanguages.isSupported(stt.selectedLanguage)
                    ? stt.selectedLanguage
                    : WhisperLanguages.auto,
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2A2E),
                items: langs
                    .map(
                      (v) => DropdownMenuItem<String>(
                        value: v,
                        child: Text(
                          'Language: ${WhisperLanguages.labelFor(v)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  stt.setSelectedLanguage(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSttModelLibrary(BuildContext context, SttModelController stt) {
    final state = stt.catalogState;
    final downloading = stt.downloading;
    final progress = stt.downloadProgress;
    final err = stt.downloadError;

    if (state == SttCatalogState.loading || state == SttCatalogState.idle) {
      return GlassPanel(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading STT models...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state == SttCatalogState.error) {
      return GlassPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              stt.catalogError ?? 'Failed to load STT models',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => stt.refreshCatalog(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final items = stt.catalogItems;
    final installedIds = stt.installedModels.map((m) => m.id).toSet();

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (downloading && progress != null) ...[
            _buildSttDownloadProgress(context, progress, stt),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 12),
          ],

          if (!downloading && err != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                err,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No STT models available',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final model = entry.value;
              final isInstalled = installedIds.contains(model.id);

              return Column(
                children: [
                  if (index > 0)
                    const Divider(height: 1, color: Colors.white12),
                  _buildSttModelTile(
                    context,
                    model: model,
                    isInstalled: isInstalled,
                    isDisabled: downloading,
                    onDownload: () =>
                        _handleSttDownload(context, model, isInstalled, stt),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSttDownloadProgress(
    BuildContext context,
    SttDownloadProgress progress,
    SttModelController stt,
  ) {
    final phaseText = switch (progress.phase) {
      'coreml' => 'Downloading CoreML…',
      'extract' => 'Extracting CoreML…',
      _ => 'Downloading model…',
    };

    final isIndeterminate =
        progress.phase == 'extract' || progress.totalBytes <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                phaseText,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => stt.cancelDownload(),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: isIndeterminate ? null : progress.fraction,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 8),
        if (!isIndeterminate)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.percent}%',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                progress.totalBytes > 0
                    ? '${formatBytes(progress.receivedBytes)} / ${formatBytes(progress.totalBytes)}'
                    : formatBytes(progress.receivedBytes),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Text(
                formatSpeed(progress.speedBytesPerSecond),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSttModelTile(
    BuildContext context, {
    required RemoteSttModelDescriptor model,
    required bool isInstalled,
    required bool isDisabled,
    required VoidCallback onDownload,
  }) {
    final hasCoreMl = model.config.coreML != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isInstalled
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isInstalled ? Icons.check_circle_rounded : Icons.mic_rounded,
              size: 22,
              color: isInstalled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.display.name.isNotEmpty ? model.display.name : model.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Whisper',
                    '${model.config.variant} ${model.config.quantization}',
                    if (model.approximateSize?.isNotEmpty ?? false)
                      model.approximateSize,
                    if (hasCoreMl) 'CoreML optional',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                if (model.display.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    model.display.description.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isInstalled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ready',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            )
          else
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: isDisabled ? null : onDownload,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Get',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleSttDownload(
    BuildContext context,
    RemoteSttModelDescriptor model,
    bool isInstalled,
    SttModelController stt,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    if (isInstalled) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Model already downloaded.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await stt.startDownload(model);
    if (!mounted) return;
    await stt.refreshInstalled();

    final err = stt.downloadError;
    if (err == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Download complete!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteStt(
    BuildContext context,
    InstalledSttModel model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete STT Model'),
        content: Text('Are you sure you want to delete ${model.id}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      final sttController = ref.read(sttModelControllerProvider);
      await sttController.deleteModel(model);
    }
  }
}
