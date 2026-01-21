import 'package:flutter/material.dart';

import 'glass_panel.dart';
import 'glass_pill.dart';

class GlassIconButton extends StatelessWidget {
  const GlassIconButton.pill({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  }) : _variant = _GlassIconButtonVariant.pill;

  const GlassIconButton.panel({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  }) : _variant = _GlassIconButtonVariant.panel;

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final _GlassIconButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case _GlassIconButtonVariant.pill:
        return GlassPill(
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          ),
        );
      case _GlassIconButtonVariant.panel:
        return GlassPanel(
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
}

enum _GlassIconButtonVariant { pill, panel }
