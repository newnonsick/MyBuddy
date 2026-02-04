import 'dart:math' as math;
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
    this.elevation = 10,
    this.borderOpacity = 0.18,
    this.highlightOpacity = 0.18,
    this.noiseOpacity = 0.018,
    this.enableBlur = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsets padding;
  final Color startColor;
  final double elevation;
  final double borderOpacity;
  final double highlightOpacity;
  final double noiseOpacity;
  final bool enableBlur;

  static const Color _kInk0 = Color(0xFF000000);
  static const Color _kInk1 = Color(0xFF09090A);
  static const Color _kInk2 = Color(0xFF121214);
  static const Color _kInk3 = Color(0xFF1A1A1D);

  static Color blackTintFrom(Color? tint, {double baseAlpha = 0.28}) {
    if (tint == null) {
      return _kInk0.withValues(alpha: baseAlpha);
    }

    final strength = (1.0 - tint.computeLuminance()).clamp(0.0, 1.0);
    final a = (baseAlpha + 0.18 * strength).clamp(0.12, 0.60);
    return _kInk0.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final tint = startColor;

    final baseDecoration = BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(tint, _kInk3.withValues(alpha: 0.55)),
          _kInk1.withValues(alpha: 0.62),
          _kInk0.withValues(alpha: 0.70),
        ],
        stops: const [0.0, 0.55, 1.0],
      ),
      border: Border.all(
        color: _kInk2.withValues(alpha: borderOpacity),
        width: 1,
      ),
    );

    final sheenDecoration = BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _kInk2.withValues(alpha: highlightOpacity * 0.65),
          Colors.transparent,
          _kInk0.withValues(alpha: highlightOpacity * 0.95),
        ],
        stops: const [0.0, 0.60, 1.0],
      ),
    );

    final content = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: DecoratedBox(decoration: baseDecoration)),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(decoration: sheenDecoration),
          ),
        ),
        if (noiseOpacity > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassNoisePainter(opacity: noiseOpacity),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        Padding(padding: padding, child: child),
      ],
    );

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: enableBlur && blurSigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: content,
            )
          : content,
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: _kInk0.withValues(alpha: 0.32),
              blurRadius: elevation,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: clipped,
      ),
    );
  }
}

class _GlassNoisePainter extends CustomPainter {
  _GlassNoisePainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final seed = (size.width * 13 + size.height * 7).round();
    final random = math.Random(seed);

    const cell = 18.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();

    final darkA = Paint()
      ..color = const Color(0xFF1A1A1D).withValues(alpha: opacity * 1.10)
      ..blendMode = BlendMode.softLight;
    final darkB = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: opacity * 0.85)
      ..blendMode = BlendMode.softLight;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final dx = x * cell + random.nextDouble() * cell;
        final dy = y * cell + random.nextDouble() * cell;
        final r = 0.4 + random.nextDouble() * 0.9;

        canvas.drawCircle(Offset(dx, dy), r, random.nextBool() ? darkA : darkB);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassNoisePainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}
