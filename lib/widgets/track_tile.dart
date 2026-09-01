import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.isActive = false,
    this.onMore,
  });

  final Track track;
  final VoidCallback onTap;
  final bool isActive;

  /// When set, shows a trailing "more" button in place of the duration
  /// label (favorite/add-to-playlist actions — screens supply the menu so
  /// this widget stays decoupled from [LibraryManager]).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: SizedBox(
                width: 48,
                height: 48,
                child: track.thumbnailUrl == null
                    ? Container(color: AppColors.surfaceRaised)
                    : CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: AppColors.surfaceRaised),
                        errorWidget: (_, _, _) =>
                            Container(color: AppColors.surfaceRaised),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? AppColors.accent
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (track.artist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onMore != null)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: AppColors.textSecondary,
                onPressed: onMore,
              )
            else if (track.durationSeconds != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatDuration(track.duration!),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
