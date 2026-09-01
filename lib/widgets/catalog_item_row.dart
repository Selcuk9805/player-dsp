import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/catalog_item.dart';
import '../theme/app_theme.dart';

/// Horizontal row of square cover cards — used for albums/playlists on
/// Home, Artist, and Search screens.
class CatalogItemRow extends StatelessWidget {
  const CatalogItemRow({super.key, required this.items, required this.onTap});

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: SizedBox(
              width: 140,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                onTap: () => onTap(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: SizedBox(
                        width: 140,
                        height: 140,
                        child: item.thumbnailUrl == null
                            ? Container(color: AppColors.surfaceRaised)
                            : CachedNetworkImage(
                                imageUrl: item.thumbnailUrl!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal row of circular avatars — used for artists.
class CatalogItemCircleRow extends StatelessWidget {
  const CatalogItemCircleRow({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: SizedBox(
              width: 84,
              child: InkWell(
                borderRadius: BorderRadius.circular(42),
                onTap: () => onTap(item),
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: item.thumbnailUrl == null
                            ? Container(color: AppColors.surfaceRaised)
                            : CachedNetworkImage(
                                imageUrl: item.thumbnailUrl!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
