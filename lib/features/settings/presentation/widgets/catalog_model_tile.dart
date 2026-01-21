import 'package:flutter/material.dart';

import 'package:mybuddy/core/model/model_descriptor.dart';
import 'package:mybuddy/core/utils/format_bytes.dart';
import 'package:mybuddy/shared/widgets/glass/glass.dart';

class CatalogModelTile extends StatelessWidget {
  const CatalogModelTile({
    super.key,
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
    return GlassPanel(
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
