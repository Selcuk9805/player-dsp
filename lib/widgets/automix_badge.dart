import 'package:flutter/material.dart';

import '../controllers/managers/automix_manager.dart';
import '../models/transition_plan.dart';
import '../theme/app_theme.dart';

class AutomixBadge extends StatelessWidget {
  const AutomixBadge({super.key, required this.manager});

  final AutomixManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final state = manager.badgeState;
        if (state == AutomixBadgeState.hidden) return const SizedBox.shrink();

        final color = switch (state) {
          AutomixBadgeState.red => AppColors.automixRed,
          AutomixBadgeState.yellow => AppColors.automixYellow,
          AutomixBadgeState.green => AppColors.automixGreen,
          AutomixBadgeState.hidden => Colors.transparent,
        };
        final label = switch (state) {
          AutomixBadgeState.red => 'Automix',
          AutomixBadgeState.yellow => 'Calculating…',
          AutomixBadgeState.green => _greenLabel(manager.currentPlan),
          AutomixBadgeState.hidden => '',
        };

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _greenLabel(TransitionPlan? plan) {
    if (plan == null) return 'Automix';
    final bpm = plan.sync.targetBpm.round();
    final key = plan.trackBAutomation.camelotKey;
    return key != null ? '$bpm BPM · $key' : '$bpm BPM';
  }
}
