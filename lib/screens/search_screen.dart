import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../models/catalog_item.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';

enum _SearchState { idle, loading, results, unreachable, error }

const _categories = ['songs', 'albums', 'artists', 'playlists'];
const _categoryLabels = [
  'Şarkılar',
  'Albümler',
  'Sanatçılar',
  'Çalma Listeleri',
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.catalogService,
    required this.playerController,
    required this.library,
  });

  final CatalogService catalogService;
  final PlayerController playerController;
  final LibraryManager library;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final TabController _tabController;
  Timer? _debounce;
  int _requestToken = 0;

  _SearchState _state = _SearchState.idle;
  Map<String, List<CatalogItem>> _resultsByCategory = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _state = _SearchState.idle);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String query) async {
    final token = ++_requestToken;
    setState(() => _state = _SearchState.loading);
    try {
      final results = await Future.wait(
        _categories.map((c) => widget.catalogService.search(query, filter: c)),
      );
      if (token != _requestToken || !mounted) return;
      setState(() {
        _resultsByCategory = Map.fromIterables(_categories, results);
        _state = _SearchState.results;
      });
    } on CatalogUnreachableException {
      if (token != _requestToken || !mounted) return;
      setState(() => _state = _SearchState.unreachable);
    } catch (_) {
      if (token != _requestToken || !mounted) return;
      setState(() => _state = _SearchState.error);
    }
  }

  void _openItem(CatalogItem item) {
    switch (item.type) {
      case 'song':
        widget.playerController.playFromSearch(item.toTrack());
        break;
      case 'album':
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
        break;
      case 'artist':
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
        break;
      case 'playlist':
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
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ara'),
        bottom: _state == _SearchState.results
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _categoryLabels.map((l) => Tab(text: l)).toList(),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) {
                _debounce?.cancel();
                if (q.trim().isNotEmpty) _runSearch(q.trim());
              },
              decoration: const InputDecoration(
                hintText: 'Şarkı, sanatçı, albüm veya çalma listesi ara...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _SearchState.idle:
        return const _CenteredHint(
          icon: Icons.music_note_rounded,
          text: 'Aramaya başlamak için bir şarkı, sanatçı veya albüm yaz.',
        );
      case _SearchState.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        );
      case _SearchState.unreachable:
        return _CenteredHint(
          icon: Icons.cloud_off_rounded,
          text: 'Sunucuya ulaşılamıyor.\nAyarlardan DSP sunucu adresini kontrol et.',
          action: TextButton(
            onPressed: () {
              final q = _controller.text.trim();
              if (q.isNotEmpty) _runSearch(q);
            },
            child: const Text('Tekrar dene'),
          ),
        );
      case _SearchState.error:
        return const _CenteredHint(
          icon: Icons.error_outline_rounded,
          text: 'Bir hata oluştu.',
        );
      case _SearchState.results:
        return AnimatedBuilder(
          animation: widget.playerController,
          builder: (context, _) => TabBarView(
            controller: _tabController,
            children: _categories.map((category) {
              final items = _resultsByCategory[category] ?? const [];
              if (items.isEmpty) {
                return const _CenteredHint(
                  icon: Icons.search_off_rounded,
                  text: 'Sonuç bulunamadı.',
                );
              }
              if (category == 'songs') {
                return ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.lg,
                    top: AppSpacing.sm,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return TrackTile(
                      track: item.toTrack(),
                      isActive:
                          widget.playerController.currentTrack ==
                          item.toTrack(),
                      onTap: () => _openItem(item),
                      onMore: () => showTrackOptionsSheet(
                        context,
                        track: item.toTrack(),
                        library: widget.library,
                      ),
                    );
                  },
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: category == 'artists' ? 0.75 : 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => category == 'artists'
                    ? _ArtistGridTile(item: items[index], onTap: _openItem)
                    : _CoverGridTile(item: items[index], onTap: _openItem),
              );
            }).toList(),
          ),
        );
    }
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _CoverGridTile extends StatelessWidget {
  const _CoverGridTile({required this.item, required this.onTap});

  final CatalogItem item;
  final ValueChanged<CatalogItem> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: () => onTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: item.thumbnailUrl == null
                  ? Container(color: AppColors.surfaceRaised)
                  : Image.network(item.thumbnailUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
    );
  }
}

class _ArtistGridTile extends StatelessWidget {
  const _ArtistGridTile({required this.item, required this.onTap});

  final CatalogItem item;
  final ValueChanged<CatalogItem> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onTap(item),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipOval(
              child: item.thumbnailUrl == null
                  ? Container(color: AppColors.surfaceRaised)
                  : Image.network(item.thumbnailUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
