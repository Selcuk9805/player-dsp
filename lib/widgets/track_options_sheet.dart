import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

// BoxDecoration requires a *uniform* Border whenever borderRadius is set —
// a non-uniform one (e.g. a brighter top edge) silently fails to paint
// instead of throwing, which cost a long debugging session to track down.
// GlassSurface's own top-highlight overlay already gives these sheets their
// "light catching glass" edge, so a plain uniform hairline is enough here.
const _sheetBorder = Border.fromBorderSide(
  BorderSide(color: Colors.white24, width: 1),
);
const _sheetRadius = BorderRadius.vertical(
  top: Radius.circular(AppSpacing.radiusLg),
);

/// The "..." menu attached to a [TrackTile]'s [TrackTile.onMore] — favorite
/// toggle + add-to-playlist, backed by [LibraryManager].
void showTrackOptionsSheet(
  BuildContext context, {
  required Track track,
  required LibraryManager library,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final isFavorite = library.isFavorite(track);
        return GlassSurface(
          tint: AppColors.surface,
          tintOpacity: 0.9,
          borderRadius: _sheetRadius,
          border: _sheetBorder,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.sm),
                ListTile(
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite ? AppColors.accent : null,
                  ),
                  title: Text(
                    isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
                  ),
                  onTap: () => library.toggleFavorite(track),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Çalma listesine ekle'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showAddToPlaylistSheet(
                      context,
                      track: track,
                      library: library,
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _showAddToPlaylistSheet(
  BuildContext context, {
  required Track track,
  required LibraryManager library,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final playlists = library.playlists;
        return GlassSurface(
          tint: AppColors.surface,
          tintOpacity: 0.9,
          borderRadius: _sheetRadius,
          border: _sheetBorder,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Çalma Listesine Ekle',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Henüz çalma listen yok.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final alreadyIn = playlist.tracks.contains(track);
                        return ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(playlist.name),
                          trailing: alreadyIn
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.accent,
                                )
                              : null,
                          onTap: alreadyIn
                              ? null
                              : () {
                                  library.addTrackToPlaylist(
                                    playlist.id,
                                    track,
                                  );
                                  Navigator.of(sheetContext).pop();
                                },
                        );
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Yeni çalma listesi oluştur'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _createPlaylistAndAdd(
                      context,
                      track: track,
                      library: library,
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _createPlaylistAndAdd(
  BuildContext context, {
  required Track track,
  required LibraryManager library,
}) async {
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Yeni Çalma Listesi'),
      content: TextField(
        controller: nameController,
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
              Navigator.of(dialogContext).pop(nameController.text.trim()),
          child: const Text('Oluştur'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return;
  final playlist = library.createPlaylist(name);
  await library.addTrackToPlaylist(playlist.id, track);
}
