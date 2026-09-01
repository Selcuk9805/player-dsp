import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/automix_badge.dart';
import '../widgets/automix_pulse_color.dart';
import '../widgets/queue_sheet.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double? _dragSeconds;

  void _openQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QueueSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final track = widget.controller.currentTrack;
        final accent = widget.controller.accentColor ?? AppColors.accent;
        final duration = widget.controller.duration;
        final durationSeconds = duration?.inSeconds.toDouble() ?? 0;
        final positionSeconds =
            _dragSeconds ?? widget.controller.position.inSeconds.toDouble();

        if (track == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Hiçbir şey çalmıyor',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Şimdi Çalıyor',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white,
                ),
                onPressed: widget.controller.queue.queue.isEmpty
                    ? null
                    : _openQueue,
              ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Ambient blurred cover-art background.
              if (track.thumbnailUrl != null)
                CachedNetworkImage(
                  imageUrl: track.thumbnailUrl!,
                  fit: BoxFit.cover,
                )
              else
                Container(color: AppColors.background),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: Container(
                    color: AppColors.background.withValues(alpha: 0.4),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: 0.35),
                        AppColors.background.withValues(alpha: 0.75),
                        AppColors.background,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Cap the art size so it can't blow past the viewport on
                    // short/wide (desktop) windows — it also can't just use
                    // full width like on a phone, since that would make it
                    // taller than the window on anything wider than tall.
                    final artSize = [
                      constraints.maxWidth - AppSpacing.lg * 2,
                      constraints.maxHeight * 0.42,
                      380.0,
                    ].reduce((a, b) => a < b ? a : b);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            Hero(
                              tag: 'album-art-${track.videoId}',
                              child: PhysicalModel(
                                color: Colors.transparent,
                                elevation: 24,
                                shadowColor: accent.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusLg,
                                ),
                                child: SizedBox(
                                  width: artSize,
                                  height: artSize,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusLg,
                                    ),
                                    child: track.thumbnailUrl == null
                                        ? Container(
                                            color: AppColors.surfaceRaised,
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: track.thumbnailUrl!,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Text(
                              track.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                            ),
                            if (track.artist != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                track.artist!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            AutomixBadge(manager: widget.controller.automix),
                            const SizedBox(height: AppSpacing.lg),
                            AutomixPulseColor(
                              active: widget.controller.isAutomixCrossfading,
                              builder: (context, pulseColor) =>
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      boxShadow:
                                          widget.controller.isAutomixCrossfading
                                          ? [
                                              BoxShadow(
                                                color: pulseColor.withValues(
                                                  alpha: 0.45,
                                                ),
                                                blurRadius: 24,
                                                spreadRadius: 1,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        activeTrackColor:
                                            widget
                                                .controller
                                                .isAutomixCrossfading
                                            ? pulseColor
                                            : accent,
                                        thumbColor:
                                            widget
                                                .controller
                                                .isAutomixCrossfading
                                            ? pulseColor
                                            : accent,
                                        overlayColor:
                                            (widget
                                                        .controller
                                                        .isAutomixCrossfading
                                                    ? pulseColor
                                                    : accent)
                                                .withValues(alpha: 0.15),
                                        inactiveTrackColor: Colors.white
                                            .withValues(alpha: 0.15),
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                      ),
                                      child: Slider(
                                        value: positionSeconds.clamp(
                                          0,
                                          durationSeconds == 0
                                              ? 1
                                              : durationSeconds,
                                        ),
                                        max: durationSeconds == 0
                                            ? 1
                                            : durationSeconds,
                                        onChanged: durationSeconds == 0
                                            ? null
                                            : (v) => setState(
                                                () => _dragSeconds = v,
                                              ),
                                        onChangeEnd: (v) {
                                          widget.controller.seek(
                                            Duration(seconds: v.round()),
                                          );
                                          setState(() => _dragSeconds = null);
                                        },
                                      ),
                                    ),
                                  ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    formatDuration(
                                      Duration(
                                        seconds: positionSeconds.round(),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    duration == null
                                        ? '--:--'
                                        : formatDuration(duration),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  iconSize: 34,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  onPressed: widget.controller.skipToPrevious,
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                if (widget.controller.isLoading ||
                                    widget.controller.isBuffering)
                                  SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: CircularProgressIndicator(
                                      color: accent,
                                    ),
                                  )
                                else
                                  _PlayPauseButton(
                                    isPlaying: widget.controller.isPlaying,
                                    color: accent,
                                    onPressed:
                                        widget.controller.togglePlayPause,
                                  ),
                                const SizedBox(width: AppSpacing.lg),
                                IconButton(
                                  iconSize: 34,
                                  icon: const Icon(Icons.skip_next_rounded),
                                  onPressed: widget.controller.queue.hasNext
                                      ? widget.controller.skipToNext
                                      : null,
                                ),
                              ],
                            ),
                            if (widget.controller.errorMessage != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                widget.controller.errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.automixRed,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.color,
    required this.onPressed,
  });

  final bool isPlaying;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 8,
      shadowColor: color.withValues(alpha: 0.6),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 38,
            color: Colors.black.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
