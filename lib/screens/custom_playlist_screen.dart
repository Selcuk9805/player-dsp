import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/custom_playlist.dart';
import '../theme/app_theme.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';

class CustomPlaylistScreen extends StatelessWidget {
  const CustomPlaylistScreen({
    super.key,
    required this.playlistId,
    required this.library,
    required this.playerController,
  });

  final String playlistId;
  final LibraryManager library;
  final PlayerController playerController;

  Future<void> _rename(BuildContext context, CustomPlaylist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Çalma Listesini Yeniden Adlandır'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await library.renamePlaylist(playlist.id, name);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Çalma listesi silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.deletePlaylist(playlistId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([library, playerController]),
      builder: (context, _) {
        CustomPlaylist? found;
        for (final p in library.playlists) {
          if (p.id == playlistId) {
            found = p;
            break;
          }
        }
        if (found == null) {
          return const Scaffold(
            body: Center(child: Text('Çalma listesi bulunamadı.')),
          );
        }
        final playlist = found;
        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _rename(context, playlist);
                  if (value == 'delete') _delete(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Yeniden adlandır'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
            ],
          ),
          body: playlist.tracks.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Bu çalma listesi boş.\nBir şarkının yanındaki menüden ekleyebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () =>
                              playerController.playFromList(playlist.tracks),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Tümünü Çal'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: playlist.tracks.length,
                        itemBuilder: (context, index) {
                          final track = playlist.tracks[index];
                          return TrackTile(
                            track: track,
                            isActive: playerController.currentTrack == track,
                            onTap: () => playerController.playFromList(
                              playlist.tracks,
                              startIndex: index,
                            ),
                            onMore: () => showTrackOptionsSheet(
                              context,
                              track: track,
                              library: library,
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
