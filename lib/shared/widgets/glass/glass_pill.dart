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
      blurSigma: 0,
      enableBlur: false,
      padding: padding,
      startColor: GlassSurface.blackTintFrom(tint, baseAlpha: 0.26),
      elevation: 10,
      borderOpacity: 0.24,
      highlightOpacity: 0.16,
      noiseOpacity: 0,
      child: child,
    );
  }
}
