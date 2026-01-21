import 'package:flutter/material.dart';

import 'glass_surface.dart';

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget child;
  final Color? tint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(999),
      blurSigma: 16,
      padding: padding,
      startColor: (tint ?? Colors.white.withValues(alpha: 0.12)),
      child: child,
    );
  }
}
