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
    _tabs = TabController(length: 2, vsync: this);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Download'),
            Tab(text: 'Select'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([widget.models, widget.app]),
        builder: (context, _) {
          return TabBarView(
            controller: _tabs,
            children: [_buildDownloadTab(context), _buildSelectTab(context)],
          );
        },
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Downloading…'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (progress.totalBytes <= 0)
                        ? null
                        : progress.fraction,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${progress.percent}% · ${formatSpeed(progress.speedBytesPerSecond)}',
                  ),
                  if (progress.totalBytes > 0)
                    Text(
                      '${formatBytes(progress.receivedBytes)} / ${formatBytes(progress.totalBytes)}',
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
          ),
          const SizedBox(height: 12),
        ],
        if (!downloading && err != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                err,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final m in items)
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
        RadioGroup<String>(
          groupValue: pendingId,
          onChanged: (v) {
            if (installing) return;
            widget.models.setPendingSelection(v);
          },
          child: Column(
            children: [
              for (final m in installed)
                RadioListTile<String>(
                  value: m.id,
                  title: Text(m.id),
                  subtitle: Text(
                    '${m.config.type} · maxTokens=${m.config.maxTokens} · tokenBuffer=${m.config.tokenBuffer}',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.app.llmError != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.app.llmError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
    return Card(
      child: ListTile(
        title: Text(model.id),
        subtitle: Text(
          '${model.config.type} · ${model.fileName}'
          '${model.approximateSize == null || model.approximateSize!.trim().isEmpty ? '' : '\nApprox: ${model.approximateSize}'}'
          '\nMin size: ${model.expectedMinBytes == null ? 'n/a' : formatBytes(model.expectedMinBytes!)}',
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
