import 'package:flutter/material.dart';

import 'glass_surface.dart';

class GlassChatBubble extends StatelessWidget {
  const GlassChatBubble({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: borderRadius,
      blurSigma: 14,
      startColor: GlassSurface.blackTintFrom(tint, baseAlpha: 0.26),
      padding: padding,
      child: child,
    );
  }
}
