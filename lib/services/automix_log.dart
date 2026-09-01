import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Appends automix telemetry to a file as well as the debug console.
///
/// `debugPrint` alone is only readable when the app is launched from a tooling
/// session (`flutter run`, an IDE, `adb logcat`). Running the built Windows
/// executable directly — which is how this gets listened to in practice —
/// discards it entirely, so the one measurement that cannot be taken offline
/// (what the audio engine actually did, on a real device, at transition time)
/// was also the one measurement impossible to collect.
///
/// The file is the collectable artifact: play a few transitions, then read
/// [logPath] and the whole session's timing is there.
class AutomixLog {
  static IOSink? _sink;
  static String? _path;
  static Future<void>? _opening;

  /// Where the log is being written, once [init] has completed. Null until then.
  static String? get logPath => _path;

  /// Keeps one session's telemetry from growing without bound across a long
  /// listening session. Each transition writes a handful of short lines, so this
  /// holds many thousands of them.
  static const _maxBytes = 4 * 1024 * 1024;

  /// Opens the log. Safe to call more than once; failures are swallowed, since
  /// losing telemetry must never take playback down with it.
  static Future<void> init() {
    return _opening ??= _open();
  }

  static Future<void> _open() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/auravibe_automix.log');

      // Truncate rather than rotate: this is a debugging aid read right after a
      // listening session, not an audit trail worth preserving across runs.
      if (await file.exists() && await file.length() > _maxBytes) {
        await file.delete();
      }

      _sink = file.openWrite(mode: FileMode.append);
      _path = file.path;
      write('--- session started ${DateTime.now().toIso8601String()} ---');
      debugPrint('[automix] telemetry log: ${file.path}');
    } catch (e) {
      debugPrint('[automix] could not open telemetry log (non-fatal): $e');
    }
  }

  /// Writes one line, to both the console and the file.
  static void write(String message) {
    debugPrint('[automix] $message');
    try {
      _sink?.writeln('${DateTime.now().toIso8601String()}  $message');
    } catch (_) {
      // A broken sink must not interrupt a crossfade.
    }
  }

  static Future<void> dispose() async {
    final sink = _sink;
    _sink = null;
    _opening = null;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
  }
}
