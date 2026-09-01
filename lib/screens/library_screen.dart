import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../theme/app_theme.dart';
import 'custom_playlist_screen.dart';
import 'favorites_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.playerController,
  });

  final LibraryManager library;
  final PlayerController playerController;

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Yeni Çalma Listesi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Çalma listesi adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      library.createPlaylist(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitaplığım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _createPlaylist(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final playlists = library.playlists;
          return ListView(
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfaceRaised,
                  child: Icon(Icons.favorite_rounded, color: AppColors.accent),
                ),
                title: const Text('Favoriler'),
                subtitle: Text('${library.favorites.length} şarkı'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FavoritesScreen(
                      library: library,
                      playerController: playerController,
                    ),
                  ),
                ),
              ),
              const Divider(color: AppColors.surfaceBorder, height: 1),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: Text(
                      'Henüz çalma listen yok.\nSağ üstteki + ile yeni bir tane oluştur.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...playlists.map(
                  (playlist) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.surfaceRaised,
                      child: Icon(
                        playlist.sourcePlaylistId != null
                            ? Icons.bookmark_rounded
                            : Icons.queue_music_rounded,
                      ),
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.tracks.length} şarkı'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomPlaylistScreen(
                          playlistId: playlist.id,
                          library: library,
                          playerController: playerController,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
