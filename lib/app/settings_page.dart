import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/model/model_descriptor.dart';
import '../core/utils/format_bytes.dart';
import 'app_controller.dart';
import 'model_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.models, required this.app});

  final ModelController models;
  final AppController app;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.models.loadLocalState();
      await widget.models.refreshInstalled();
      await widget.models.refreshCatalog();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  _GlassIconButton(
                    tooltip: 'Back',
                    icon: Icons.chevron_left,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Models and preferences',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _GlassPanel(
                padding: const EdgeInsets.all(6),
                child: TabBar(
                  controller: _tabs,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  tabs: const [
                    Tab(text: 'Download'),
                    Tab(text: 'Select'),
                    Tab(text: 'Prefs'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([widget.models, widget.app]),
                builder: (context, _) {
                  return TabBarView(
                    controller: _tabs,
                    children: [
                      _buildDownloadTab(context),
                      _buildSelectTab(context),
                      _buildPreferencesTab(context),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadTab(BuildContext context) {
    final state = widget.models.catalogState;
    final downloading = widget.models.downloading;
    final progress = widget.models.downloadProgress;
    final err = widget.models.downloadError;

    if (state == CatalogState.loading || state == CatalogState.idle) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state == CatalogState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _GlassPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.models.catalogError ?? 'Failed to load catalog.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => widget.models.refreshCatalog(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final items = widget.models.catalogItems;
    if (items.isEmpty) {
      return const Center(child: Text('No models in catalog.'));
    }

    final installedIds = widget.models.installedModels.map((m) => m.id).toSet();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (downloading && progress != null) ...[
          _GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Downloading…'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (progress.totalBytes <= 0)
                        ? null
                        : progress.fraction,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${progress.percent}% · ${formatSpeed(progress.speedBytesPerSecond)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (progress.totalBytes > 0)
                  Text(
                    '${formatBytes(progress.receivedBytes)} / ${formatBytes(progress.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => widget.models.cancelDownload(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!downloading && err != null) ...[
          _GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Text(
              err,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final m in items) ...[
          _CatalogModelTile(
            model: m,
            isInstalled: installedIds.contains(m.id),
            disabled: downloading,
            onDownload: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (installedIds.contains(m.id)) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Model already downloaded.')),
                );
                await widget.models.refreshInstalled();
                return;
              }

              await widget.models.startDownload(m);
              if (!mounted) return;
              await widget.models.refreshInstalled();

              final err = widget.models.downloadError;
              if (err == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Download completed.')),
                );
              }
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSelectTab(BuildContext context) {
    final installed = widget.models.installedModels;
    final pendingId = widget.models.pendingSelectionId;

    if (installed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No downloaded models yet. Go to Download tab.'),
        ),
      );
    }

    final installing = widget.app.installingLlm;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _GlassPanel(
          padding: const EdgeInsets.all(6),
          child: RadioGroup<String>(
            groupValue: pendingId,
            onChanged: (v) {
              if (installing) return;
              widget.models.setPendingSelection(v);
            },
            child: Column(
              children: [
                for (final m in installed) ...[
                  RadioListTile<String>(
                    value: m.id,
                    title: Text(m.id),
                    subtitle: Text(
                      '${m.config.type} · maxTokens=${m.config.maxTokens} · tokenBuffer=${m.config.tokenBuffer}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.app.llmError != null) ...[
          _GlassPanel(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.app.llmError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: installing
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await widget.models.commitSelection();
                  await widget.app.activateSelectedModel();

                  if (!mounted) return;
                  if (widget.app.llmInstalled) {
                    navigator.pop();
                  }
                },
          child: installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Use selected model'),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: Download and selection are separate. Download in the Download tab first, then come back here to choose what to use.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPreferencesTab(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Appearance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _GlassPanel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: widget.app.hideChatLog,
            onChanged: (value) => widget.app.setHideChatLog(value),
            title: const Text('Hide chat log'),
            subtitle: const Text('Hide all messages from the screen.'),
          ),
        ),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                tone.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }
}

class _CatalogModelTile extends StatelessWidget {
  const _CatalogModelTile({
    required this.model,
    required this.isInstalled,
    required this.disabled,
    required this.onDownload,
  });

  final RemoteModelDescriptor model;
  final bool isInstalled;
  final bool disabled;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(model.id),
        subtitle: Text(
          '${model.config.type} · ${model.fileName}'
          '${model.approximateSize == null || model.approximateSize!.trim().isEmpty ? '' : '\nApprox: ${model.approximateSize}'}'
          '\nMin size: ${model.expectedMinBytes == null ? 'n/a' : formatBytes(model.expectedMinBytes!)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.70),
            height: 1.25,
          ),
        ),
        isThreeLine: true,
        trailing: isInstalled
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check),
                  SizedBox(width: 6),
                  Text('Downloaded'),
                ],
              )
            : FilledButton(
                onPressed: disabled ? null : () => onDownload(),
                child: const Text('Download'),
              ),
      ),
    );
  }
}
