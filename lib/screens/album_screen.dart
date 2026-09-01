import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/album_detail.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_states.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.catalogService,
    required this.playerController,
    required this.library,
  });

  final String albumId;
  final CatalogService catalogService;
  final PlayerController playerController;
  final LibraryManager library;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late Future<AlbumDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.catalogService.getAlbum(widget.albumId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<AlbumDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CollectionLoading();
          }
          if (snapshot.hasError) {
            return CollectionError(
              error: snapshot.error,
              onRetry: () => setState(
                () => _future = widget.catalogService.getAlbum(widget.albumId),
              ),
            );
          }
          final album = snapshot.data!;
          return AnimatedBuilder(
            animation: widget.playerController,
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverAppBar(title: const Text(''), pinned: false),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusLg,
                          ),
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            child: album.thumbnailUrl == null
                                ? Container(color: AppColors.surfaceRaised)
                                : CachedNetworkImage(
                                    imageUrl: album.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => Container(
                                      color: AppColors.surfaceRaised,
                                    ),
                                    errorWidget: (_, _, _) => Container(
                                      color: AppColors.surfaceRaised,
                                      child: const Icon(
                                        Icons.album_rounded,
                                        size: 64,
                                        color: AppColors.textDisabled,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          album.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (album.artist != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          InkWell(
                            onTap: album.artistId == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ArtistScreen(
                                        artistId: album.artistId!,
                                        catalogService: widget.catalogService,
                                        playerController:
                                            widget.playerController,
                                        library: widget.library,
                                      ),
                                    ),
                                  ),
                            child: Text(
                              [
                                album.artist,
                                album.year,
                              ].whereType<String>().join(' · '),
                              style: TextStyle(
                                color: album.artistId != null
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: album.tracks.isEmpty
                              ? null
                              : () => widget.playerController.playFromList(
                                  album.tracks,
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Tümünü Çal'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: album.tracks.length,
                  itemBuilder: (context, index) {
                    final track = album.tracks[index];
                    return TrackTile(
                      track: track,
                      isActive: widget.playerController.currentTrack == track,
                      onTap: () => widget.playerController.playFromList(
                        album.tracks,
                        startIndex: index,
                      ),
                      onMore: () => showTrackOptionsSheet(
                        context,
                        track: track,
                        library: widget.library,
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.lg),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
