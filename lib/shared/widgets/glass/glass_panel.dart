import 'package:flutter/material.dart';

import 'glass_surface.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blurSigma: 0,
      enableBlur: false,
      padding: padding,
      startColor: GlassSurface.blackTintFrom(tint, baseAlpha: 0.28),
      elevation: 12,
      borderOpacity: 0.22,
      highlightOpacity: 0.17,
      noiseOpacity: 0,
      child: child,
    );
  }
}
