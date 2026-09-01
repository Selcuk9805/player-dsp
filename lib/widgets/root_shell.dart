import 'package:flutter/material.dart';

import '../controllers/managers/library_manager.dart';
import '../controllers/player_controller.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';
import 'mini_player.dart';

/// Bottom-nav shell: Home/Search/Library tabs (state preserved via
/// [IndexedStack]) plus the persistent mini player docked above the nav bar.
class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.catalogService,
    required this.storage,
    required this.library,
    required this.playerController,
  });

  final CatalogService catalogService;
  final StorageService storage;
  final LibraryManager library;
  final PlayerController playerController;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;

  // Each tab gets its own nested Navigator, so drilling into an artist/album/
  // playlist pushes onto that tab's own stack — the mini player and nav bar
  // below (siblings of this IndexedStack, not inside it) stay on screen the
  // whole time, the way a real music app's persistent player does. Only
  // opening the full Now Playing screen (pushed on the *root* Navigator from
  // within MiniPlayer) covers everything.
  late final List<GlobalKey<NavigatorState>> _tabNavigatorKeys = List.generate(
    3,
    (_) => GlobalKey<NavigatorState>(),
  );

  Widget _tabNavigator(int index, WidgetBuilder rootBuilder) {
    return Navigator(
      key: _tabNavigatorKeys[index],
      onGenerateRoute: (settings) => MaterialPageRoute(builder: rootBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Android hardware/gesture back: pop the active tab's own stack (e.g.
      // out of an artist page) before letting it fall through to closing
      // the app — otherwise a nested Navigator's pushed screens would be
      // invisible to the system back button entirely.
      canPop: !(_tabNavigatorKeys[_tabIndex].currentState?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _tabNavigatorKeys[_tabIndex].currentState?.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _tabNavigator(
              0,
              (_) => HomeScreen(
                catalogService: widget.catalogService,
                storage: widget.storage,
                automixManager: widget.playerController.automix,
                playerController: widget.playerController,
                library: widget.library,
              ),
            ),
            _tabNavigator(
              1,
              (_) => SearchScreen(
                catalogService: widget.catalogService,
                playerController: widget.playerController,
                library: widget.library,
              ),
            ),
            _tabNavigator(
              2,
              (_) => LibraryScreen(
                library: widget.library,
                playerController: widget.playerController,
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiniPlayer(controller: widget.playerController),
            GlassSurface(
              tint: AppColors.surface,
              tintOpacity: 0.7,
              border: const Border(
                top: BorderSide(color: Colors.white10, width: 0.5),
              ),
              child: NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: (i) {
                  if (i == _tabIndex) {
                    _tabNavigatorKeys[i].currentState?.popUntil(
                      (r) => r.isFirst,
                    );
                  } else {
                    setState(() => _tabIndex = i);
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore_rounded),
                    label: 'Keşfet',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search_rounded),
                    selectedIcon: Icon(Icons.search_rounded),
                    label: 'Ara',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: 'Kitaplığım',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
