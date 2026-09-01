import 'package:flutter/material.dart';

import 'controllers/managers/automix_manager.dart';
import 'controllers/managers/library_manager.dart';
import 'controllers/managers/queue_manager.dart';
import 'controllers/player_controller.dart';
import 'services/automix_service.dart';
import 'services/catalog_service.dart';
import 'services/soloud_audio_service.dart';
import 'services/storage_service.dart';
import 'services/stream_service.dart';
import 'theme/app_theme.dart';
import 'widgets/root_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await StorageService.create();
  final audioService = SoloudAudioService();
  await audioService.init();

  final catalogService = CatalogService(storage);
  final streamService = StreamService(storage);
  final automixService = AutomixService(storage);
  final queueManager = QueueManager();
  final automixManager = AutomixManager(storage, automixService);
  final libraryManager = LibraryManager(storage);
  final playerController = PlayerController(
    catalogService: catalogService,
    streamService: streamService,
    audioService: audioService,
    queueManager: queueManager,
    automixManager: automixManager,
  );

  runApp(
    AuravibeApp(
      catalogService: catalogService,
      storage: storage,
      library: libraryManager,
      playerController: playerController,
    ),
  );
}

class AuravibeApp extends StatelessWidget {
  const AuravibeApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auravibe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: RootShell(
        catalogService: catalogService,
        storage: storage,
        library: library,
        playerController: playerController,
      ),
    );
  }
}
