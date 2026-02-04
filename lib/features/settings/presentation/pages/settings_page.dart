import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_controller.dart';
import '../../../../app/model_controller.dart';
import '../../../../app/providers.dart';
import '../../../../core/model/model_descriptor.dart';
import '../../../../core/model/model_store.dart';
import '../../../../core/notification/notification_service.dart';
import '../../../../core/utils/format_bytes.dart';
import '../../../../shared/widgets/glass/glass.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(modelControllerProvider);
    final app = ref.watch(appControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _notificationService,
          builder: (context, _) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context)),
                SliverToBoxAdapter(
                  child: _buildSection(
                    context,
                    icon: Icons.memory_rounded,
                    title: 'Active Model',
                    children: [_buildActiveModelCard(context, models, app)],
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSection(
                    context,
                    icon: Icons.download_rounded,
                    title: 'Model Library',
                    children: [_buildModelLibrary(context, models)],
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSection(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Preferences',
                    children: [_buildPreferencesCard(context, app)],
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GlassIconButton.panel(
            tooltip: 'Back',
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActiveModelCard(
    BuildContext context,
    ModelController models,
    AppController app,
  ) {
    final installed = models.installedModels;
    final pendingId = models.pendingSelectionId;
    final installing = app.installingLlm;

    if (installed.isEmpty) {
      return GlassPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.download_for_offline_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No Models Downloaded',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Download a model from the library below to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...installed.map((m) {
            final isActiveAndLoaded =
                m.id == models.selectedModelId && app.llmInstalled;
            final isSelected = m.id == pendingId;
            return _buildModelOption(
              context,
              model: m,
              isSelected: isSelected,
              isActive: isActiveAndLoaded,
              models: models,
              onTap: installing || isActiveAndLoaded
                  ? null
                  : () => models.setPendingSelection(m.id),
            );
          }),

          if (app.llmError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.llmError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          Builder(
            builder: (context) {
              final isAlreadyActive =
                  pendingId == models.selectedModelId && app.llmInstalled;

              return SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: installing || isAlreadyActive
                      ? null
                      : () async {
                          final navigator = Navigator.of(context);
                          await models.commitSelection();
                          await app.activateSelectedModel();
                          if (!mounted) return;
                          if (app.llmInstalled) {
                            navigator.pop();
                          }
                        },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: installing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isAlreadyActive
                              ? 'Model Already Active'
                              : 'Apply & Start Chat',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModelOption(
    BuildContext context, {
    required InstalledModel model,
    required bool isSelected,
    required bool isActive,
    required ModelController models,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : (isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white.withValues(alpha: 0.3)),
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
                            model.id,
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.config.type} • ${model.config.maxTokens} tokens',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isActive)
                  IconButton(
                    icon: Icon(
                      Icons.delete_rounded,
                      size: 20,
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.6),
                    ),
                    onPressed: () => _confirmDelete(context, model),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InstalledModel model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Model'),
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
      final models = ref.read(modelControllerProvider);
      await models.deleteModel(model);
    }
  }

  Widget _buildModelLibrary(BuildContext context, ModelController models) {
    final state = models.catalogState;
    final downloading = models.downloading;
    final progress = models.downloadProgress;
    final err = models.downloadError;

    if (state == CatalogState.loading || state == CatalogState.idle) {
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
                'Loading models...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state == CatalogState.error) {
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
              models.catalogError ?? 'Failed to load models',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => models.refreshCatalog(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final items = models.catalogItems;
    final installedIds = models.installedModels.map((m) => m.id).toSet();

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (downloading && progress != null) ...[
            _buildDownloadProgress(context, progress, models),
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
                'No models available',
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
                  _buildModelTile(
                    context,
                    model: model,
                    isInstalled: isInstalled,
                    isDisabled: downloading,
                    onDownload: () =>
                        _handleDownload(context, model, isInstalled, models),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(
    BuildContext context,
    ModelDownloadProgress progress,
    ModelController models,
  ) {
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
                'Downloading...',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => models.cancelDownload(),
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
            value: progress.totalBytes <= 0 ? null : progress.fraction,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 8),
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

  Widget _buildModelTile(
    BuildContext context, {
    required RemoteModelDescriptor model,
    required bool isInstalled,
    required bool isDisabled,
    required VoidCallback onDownload,
  }) {
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
              isInstalled
                  ? Icons.check_circle_rounded
                  : Icons.smart_toy_outlined,
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
                  model.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    model.config.type,
                    if (model.approximateSize?.isNotEmpty ?? false)
                      model.approximateSize,
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
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

  Future<void> _handleDownload(
    BuildContext context,
    RemoteModelDescriptor model,
    bool isInstalled,
    ModelController models,
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

    await models.startDownload(model);
    if (!mounted) return;
    await models.refreshInstalled();

    final err = models.downloadError;
    if (err == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Download complete!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildPreferencesCard(BuildContext context, AppController app) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildSettingsGroup(
            context,
            title: 'Appearance',
            items: [
              _buildSwitchTile(
                context,
                icon: Icons.visibility_off_rounded,
                title: 'Hide Chat Log',
                subtitle: 'Hide messages from the screen',
                value: app.hideChatLog,
                onChanged: app.setHideChatLog,
              ),
            ],
          ),

          const Divider(height: 1, color: Colors.white12),

          _buildSettingsGroup(
            context,
            title: 'Notifications',
            items: [
              _buildSwitchTile(
                context,
                icon: Icons.notifications_active_rounded,
                title: 'Daily Reminders',
                subtitle: 'Friendly reminders to chat with your buddy',
                value: _notificationService.isDailyReminderEnabled,
                onChanged: _notificationService.setDailyReminderEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: value
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
