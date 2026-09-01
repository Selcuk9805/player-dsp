import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../controllers/managers/automix_manager.dart';
import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/catalog_item.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalog_item_row.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';

enum _HomeState { loading, loaded, unreachable, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.catalogService,
    required this.storage,
    required this.automixManager,
    required this.playerController,
    required this.library,
  });

  final CatalogService catalogService;
  final StorageService storage;
  final AutomixManager automixManager;
  final PlayerController playerController;
  final LibraryManager library;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _HomeState _state = _HomeState.loading;
  List<CatalogItem> _playlists = [];
  List<CatalogItem> _artists = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _HomeState.loading);
    try {
      final charts = await widget.catalogService.charts();
      if (!mounted) return;
      setState(() {
        _playlists = charts.playlists;
        _artists = charts.artists;
        _state = _HomeState.loaded;
      });
    } on CatalogUnreachableException {
      if (!mounted) return;
      setState(() => _state = _HomeState.unreachable);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _HomeState.error);
    }
  }

  void _openPlaylist(CatalogItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(
          playlistId: item.id,
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
      appBar: AppBar(
        title: const Text('Keşfet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  storage: widget.storage,
                  automixManager: widget.automixManager,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _HomeState.loading:
        return _buildShimmer();
      case _HomeState.unreachable:
        return _buildMessage(
          Icons.cloud_off_rounded,
          'Sunucuya ulaşılamıyor.\nDSP sunucusunun çalıştığından emin olun.',
          showRetry: true,
          showSettings: true,
        );
      case _HomeState.error:
        return _buildMessage(
          Icons.error_outline_rounded,
          'Bir hata oluştu.',
          showRetry: true,
        );
      case _HomeState.loaded:
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          children: [
            if (_playlists.isNotEmpty) ...[
              const _SectionHeader('Trend Çalma Listeleri'),
              CatalogItemRow(items: _playlists, onTap: _openPlaylist),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_artists.isNotEmpty) ...[
              const _SectionHeader('Trend Sanatçılar'),
              CatalogItemCircleRow(items: _artists, onTap: _openArtist),
            ],
            if (_playlists.isEmpty && _artists.isEmpty)
              _buildMessage(
                Icons.trending_up_rounded,
                'Bu bölge için trend verisi yok.',
                showRetry: true,
              ),
          ],
        );
    }
  }

  Widget _buildMessage(
    IconData icon,
    String text, {
    bool showRetry = false,
    bool showSettings = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: AppColors.textDisabled),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  if (showRetry) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Yeniden Dene'),
                    ),
                  ],
                  if (showSettings) ...[
                    const SizedBox(height: AppSpacing.xs),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            storage: widget.storage,
                            automixManager: widget.automixManager,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Ayarları Kontrol Et'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceRaised,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        children: [
          Container(height: 20, width: 160, color: AppColors.surface),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 150,
            child: Row(
              children: List.generate(
                3,
                (_) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
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
