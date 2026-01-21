import 'package:flutter/material.dart';

import 'glass_surface.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blurSigma: 18,
      padding: padding,
      startColor: Colors.white.withValues(alpha: 0.12),
      child: child,
    );
  }
}
