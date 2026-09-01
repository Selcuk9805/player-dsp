import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';
import 'track_tile.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final queue = controller.queue.queue;
        final currentIndex = controller.queue.currentIndex;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => GlassSurface(
            tint: AppColors.surface,
            tintOpacity: 0.85,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusLg),
            ),
            // BoxDecoration silently fails to paint (not a build-time error)
            // if border isn't uniform when borderRadius is set — see the
            // comment in track_options_sheet.dart for how that was found.
            border: const Border.fromBorderSide(
              BorderSide(color: Colors.white24, width: 1),
            ),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Text(
                        'Sırada',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (controller.queue.radioEligible)
                        const Chip(
                          label: Text('Radyo', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.surfaceBorder,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      return TrackTile(
                        track: track,
                        isActive: index == currentIndex,
                        onTap: () {
                          controller.jumpToQueueIndex(index);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
