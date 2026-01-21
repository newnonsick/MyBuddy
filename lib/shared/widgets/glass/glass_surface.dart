import 'dart:ui';

import 'package:flutter/material.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.blurSigma,
    required this.padding,
    required this.startColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsets padding;
  final Color startColor;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [startColor, tone.withValues(alpha: 0.08)],
            ),
            borderRadius: borderRadius,
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
