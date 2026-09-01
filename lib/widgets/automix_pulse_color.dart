import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Drives a color that oscillates between automix green and teal while
/// [active] — used to give the seek bar / mini player progress a distinct
/// "a crossfade is happening right now" treatment instead of the plain
/// accent-colored progress. Stops (and rebuilds nothing extra) when inactive.
class AutomixPulseColor extends StatefulWidget {
  const AutomixPulseColor({
    super.key,
    required this.active,
    required this.builder,
  });

  final bool active;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  State<AutomixPulseColor> createState() => _AutomixPulseColorState();
}

class _AutomixPulseColorState extends State<AutomixPulseColor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AutomixPulseColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.builder(context, AppColors.accent);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color = Color.lerp(
          AppColors.automixGreen,
          AppColors.accentSecondary,
          _controller.value,
        )!;
        return widget.builder(context, color);
      },
    );
  }
}
