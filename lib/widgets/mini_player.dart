import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../screens/now_playing_screen.dart';
import '../theme/app_theme.dart';
import 'automix_pulse_color.dart';
import 'glass_surface.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final accent = controller.accentColor ?? AppColors.accent;
        final duration = controller.duration;
        final positionSeconds = controller.position.inMilliseconds / 1000;
        final durationSeconds = duration == null
            ? null
            : duration.inMilliseconds / 1000;

        return GlassSurface(
          tint: AppColors.surfaceRaised,
          tintOpacity: 0.78,
          border: const Border(
            top: BorderSide(color: Colors.white10, width: 0.5),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AutomixPulseColor(
                  active: controller.isAutomixCrossfading,
                  builder: (context, pulseColor) => SizedBox(
                    height: controller.isAutomixCrossfading ? 3 : 2,
                    child: LinearProgressIndicator(
                      value: durationSeconds != null && durationSeconds > 0
                          ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(
                        controller.isAutomixCrossfading ? pulseColor : accent,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NowPlayingScreen(controller: controller),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'album-art-${track.videoId}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: track.thumbnailUrl == null
                                  ? Container(color: AppColors.surfaceBorder)
                                  : CachedNetworkImage(
                                      imageUrl: track.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (controller.errorMessage != null)
                                Text(
                                  controller.errorMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.automixRed,
                                    fontSize: 12,
                                  ),
                                )
                              else if (track.artist != null)
                                Text(
                                  track.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        if (controller.isLoading || controller.isBuffering)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: Icon(
                              controller.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                            ),
                            color: accent,
                            onPressed: controller.togglePlayPause,
                          ),
                      ],
                    ),
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
