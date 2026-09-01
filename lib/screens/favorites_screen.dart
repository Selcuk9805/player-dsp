import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    super.key,
    required this.library,
    required this.playerController,
  });

  final LibraryManager library;
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoriler')),
      body: AnimatedBuilder(
        animation: Listenable.merge([library, playerController]),
        builder: (context, _) {
          final favorites = library.favorites;
          if (favorites.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Henüz favori şarkın yok.\nBir şarkının yanındaki menüden ekleyebilirsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.lg,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final track = favorites[index];
              return TrackTile(
                track: track,
                isActive: playerController.currentTrack == track,
                onTap: () =>
                    playerController.playFromList(favorites, startIndex: index),
                onMore: () => showTrackOptionsSheet(
                  context,
                  track: track,
                  library: library,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
