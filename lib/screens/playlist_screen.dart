import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/playlist_detail.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_states.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';

/// A curated (YT Music) playlist fetched live from `another-dsp` — read-only.
/// For the user's own local playlists, see `CustomPlaylistScreen`.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.playlistId,
    required this.catalogService,
    required this.playerController,
    required this.library,
  });

  final String playlistId;
  final CatalogService catalogService;
  final PlayerController playerController;
  final LibraryManager library;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<PlaylistDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.catalogService.getPlaylist(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<PlaylistDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CollectionLoading();
          }
          if (snapshot.hasError) {
            return CollectionError(
              error: snapshot.error,
              onRetry: () => setState(
                () => _future = widget.catalogService.getPlaylist(
                  widget.playlistId,
                ),
              ),
            );
          }
          final playlist = snapshot.data!;
          return AnimatedBuilder(
            animation: Listenable.merge([
              widget.playerController,
              widget.library,
            ]),
            builder: (context, _) {
              final isSaved = widget.library.isPlaylistSaved(playlist.id);
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    title: const Text(''),
                    pinned: false,
                    actions: [
                      IconButton(
                        tooltip: isSaved
                            ? 'Kitaplıktan kaldır'
                            : 'Kitaplığa kaydet',
                        icon: Icon(
                          isSaved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: isSaved ? AppColors.accent : null,
                        ),
                        onPressed: playlist.tracks.isEmpty
                            ? null
                            : () => widget.library.toggleSavedPlaylist(
                                sourcePlaylistId: playlist.id,
                                name: playlist.title,
                                tracks: playlist.tracks,
                              ),
                      ),
                    ],
                  ),
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
                              child: playlist.thumbnailUrl == null
                                  ? Container(color: AppColors.surfaceRaised)
                                  : CachedNetworkImage(
                                      imageUrl: playlist.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            playlist.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (playlist.author != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              playlist.author!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: playlist.tracks.isEmpty
                                ? null
                                : () => widget.playerController.playFromList(
                                    playlist.tracks,
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
                    itemCount: playlist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return TrackTile(
                        track: track,
                        isActive: widget.playerController.currentTrack == track,
                        onTap: () => widget.playerController.playFromList(
                          playlist.tracks,
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
              );
            },
          );
        },
      ),
    );
  }
}
