import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controllers/managers/automix_manager.dart';
import 'controllers/managers/library_manager.dart';
import 'controllers/managers/queue_manager.dart';
import 'controllers/player_controller.dart';
import 'services/automix_service.dart';
import 'services/catalog_service.dart';
import 'services/media_session.dart';
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

  await _attachMediaSession(playerController);

  runApp(
    AuravibeApp(
      catalogService: catalogService,
      storage: storage,
      library: libraryManager,
      playerController: playerController,
    ),
  );
}

/// Platforms `audio_service` actually ships an implementation for.
///
/// This app also builds for Windows and Linux, where there is no plugin behind
/// the method channel and `AudioService.init` would throw on startup — and
/// where a media session would buy nothing anyway, since a desktop app is not
/// frozen for being in the background.
const _mediaSessionPlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
};

/// Puts playback behind a foreground service, so backgrounding the app keeps
/// the audio (and the automix timers driving it) running, and gives the OS a
/// notification and lock-screen controls wired to the same controller the UI
/// uses. Absent on the desktop targets; playback there is unaffected.
Future<void> _attachMediaSession(PlayerController controller) async {
  if (!_mediaSessionPlatforms.contains(defaultTargetPlatform)) return;
  await AudioService.init(
    builder: () => MediaSessionHandler(controller),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.selcuk.auravibe.playback',
      androidNotificationChannelName: 'Müzik çalar',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
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
