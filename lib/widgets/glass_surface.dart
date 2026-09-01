import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A cheap, GPU-friendly approximation of "liquid glass" chrome — layered
/// blur + a faint vertical light gradient + a hairline edge highlight.
///
/// This is deliberately NOT true dynamic refraction (that needs a custom
/// fragment shader, which is a separate, heavier follow-up if we ever want
/// it) — just [BackdropFilter] blur plus a couple of static gradients that
/// read as "light catching glass" without the per-frame GPU cost or the
/// risk of tanking on lower-end Android devices.
///
/// Reserved for persistent chrome — mini player, nav bar, sheets — the way
/// Apple actually uses the material (toolbars/tab bars/sheets, not every
/// list row). Applying it to scrolling content would be both visually
/// noisy and needlessly expensive.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blurSigma = 24,
    this.tint = AppColors.surface,
    this.tintOpacity = 0.72,
    this.border,
    this.showTopHighlight = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color tint;
  final double tintOpacity;

  /// **Must be uniform (same color/width on every side) whenever
  /// [borderRadius] is non-zero** — [BoxDecoration] silently fails to paint
  /// (no exception, no red screen, just a blank surface) for a non-uniform
  /// border combined with rounded corners. Rely on [showTopHighlight] for a
  /// brighter top edge instead of trying to vary the border by side.
  final Border? border;
  final bool showTopHighlight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: border,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  tint,
                  Colors.white,
                  0.05,
                )!.withValues(alpha: tintOpacity),
                tint.withValues(alpha: tintOpacity),
              ],
            ),
          ),
          child: Stack(
            children: [
              if (showTopHighlight)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.4),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
