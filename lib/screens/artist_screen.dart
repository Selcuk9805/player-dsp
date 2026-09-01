import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/artist_detail.dart';
import '../models/catalog_item.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalog_item_row.dart';
import '../widgets/collection_states.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.artistId,
    required this.catalogService,
    required this.playerController,
    required this.library,
  });

  final String artistId;
  final CatalogService catalogService;
  final PlayerController playerController;
  final LibraryManager library;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<ArtistDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.catalogService.getArtist(widget.artistId);
  }

  void _openAlbum(CatalogItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumScreen(
          albumId: item.id,
          catalogService: widget.catalogService,
          playerController: widget.playerController,
          library: widget.library,
        ),
      ),
    );
  }

  void _openArtist(CatalogItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistId: item.id,
          catalogService: widget.catalogService,
          playerController: widget.playerController,
          library: widget.library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<ArtistDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CollectionLoading();
          }
          if (snapshot.hasError) {
            return CollectionError(
              error: snapshot.error,
              onRetry: () => setState(
                () =>
                    _future = widget.catalogService.getArtist(widget.artistId),
              ),
            );
          }
          final artist = snapshot.data!;
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
                        ClipOval(
                          child: SizedBox(
                            width: 140,
                            height: 140,
                            child: artist.thumbnailUrl == null
                                ? Container(color: AppColors.surfaceRaised)
                                : CachedNetworkImage(
                                    imageUrl: artist.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          artist.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: artist.topSongs.isEmpty
                              ? null
                              : () => widget.playerController.playFromList(
                                  artist.topSongs,
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('En Çok Dinlenenleri Çal'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (artist.topSongs.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: _SectionLabel('En Çok Dinlenenler'),
                  ),
                  SliverList.builder(
                    itemCount: artist.topSongs.length,
                    itemBuilder: (context, index) {
                      final track = artist.topSongs[index];
                      return TrackTile(
                        track: track,
                        isActive: widget.playerController.currentTrack == track,
                        onTap: () => widget.playerController.playFromList(
                          artist.topSongs,
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
                ],
                if (artist.albums.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: _SectionLabel('Albümler')),
                  SliverToBoxAdapter(
                    child: CatalogItemRow(
                      items: artist.albums,
                      onTap: _openAlbum,
                    ),
                  ),
                ],
                if (artist.relatedArtists.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: _SectionLabel('Benzer Sanatçılar'),
                  ),
                  SliverToBoxAdapter(
                    child: CatalogItemCircleRow(
                      items: artist.relatedArtists,
                      onTap: _openArtist,
                    ),
                  ),
                ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
