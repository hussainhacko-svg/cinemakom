import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_tvos/path_provider_tvos.dart';

import 'core/downloads/downloader.dart';
import 'core/network/api_providers.dart';
import 'core/platform/platform_info.dart';
import 'core/player/av_player_engine.dart';
import 'core/storage/database.dart';
import 'data/repositories/downloads_repository.dart';
import 'data/repositories/library_repository.dart';
import 'features/player/player_controller.dart';
import 'main.dart' show noRetry, registerFontLicenses;
import 'tv/tv_app.dart';

/// Dedicated Apple TV (tvOS) entrypoint.
///
/// Kept completely separate from `lib/main.dart` so Android, iOS, macOS,
/// Linux, and Windows builds remain untouched:
/// - Does not initialize `media_kit`, `sqflite_common_ffi`, `window_manager`,
///   `background_downloader`, or mobile orientation locks.
/// - Disables offline downloads (`supportsDownloads == false`) per tvOS's
///   purgeable-storage rules and overrides [downloaderProvider] with a no-op
///   implementation so `connectivity_plus` / `background_downloader` channels
///   are never invoked.
/// - Stores the Drift SQLite database under `Library/Caches` (safe on tvOS).
/// - Uses [AvPlayerEngine] (`tvos/Runner/AppleTvHdrPlayer.swift`) for native
///   4K HDR (`AVPlayerLayer` + `AVDisplayManager`) hardware video playback.
Future<void> main() async {
  markAppleTv();
  WidgetsFlutterBinding.ensureInitialized();
  installAppleTvPathProvider();
  installAppleTvSemanticsGuard();
  registerFontLicenses();

  runApp(
    ProviderScope(
      retry: noRetry,
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(_openTvosDatabase());
          ref.onDispose(db.close);
          return db;
        }),
        downloaderProvider.overrideWithValue(const TvosNoopDownloader()),
        playerEngineFactoryProvider.overrideWith((ref) {
          final api = ref.read(apiClientProvider);
          return () => AvPlayerEngine(
            loadText: (url) => api.fetchText(url).then(_dropBom),
          );
        }),
      ],
      child: const TvApp(),
    ),
  );
}

/// Redirects `getApplicationSupportDirectory()` and
/// `getApplicationDocumentsDirectory()` to `Library/Caches` on Apple TV.
///
/// The physical tvOS sandbox only permits writes to `Library/Caches` and `tmp`:
/// `Documents` is read-only and creating `Library/Application Support` fails
/// with `errno 1`, causing `path_provider_tvos` to return `null` and
/// `getApplicationSupportDirectory()` to throw
/// [MissingPlatformDirectoryException]. Packages like `cached_network_image`
/// (`flutter_cache_manager`'s `CacheObjectProvider`) store their SQLite cache
/// index under `getApplicationSupportDirectory()`, so without this redirect
/// every network image fails to load on a physical Apple TV.
@visibleForTesting
base class AppleTvPathProvider extends PathProviderTvos {
  @override
  Future<String?> getApplicationSupportPath() => getApplicationCachePath();

  @override
  Future<String?> getApplicationDocumentsPath() => getApplicationCachePath();
}

@visibleForTesting
void installAppleTvPathProvider() {
  PathProviderPlatform.instance = AppleTvPathProvider();
}

/// Guards against semantics actions from tvOS's UIKit semantics bridge
/// (`FlutterScrollableSemanticsObject`) interfering with Cinemakom's TV
/// focus-driven scrolling and `PipelineOwner.flushSemantics()`:
///
/// - `SemanticsAction.scrollToOffset` is always dropped on Apple TV. UIKit's
///   backed `UIScrollView` fires `scrollViewDidScroll:` both synchronously
///   inside `updateSemantics()` (causing `!owner!._debugDoingSemantics`
///   assertions) and asynchronously in `idle` with `_AppleTvViewport`'s 2×
///   scaled offsets (jumping scroll views and cancelling `tvReveal`'s smooth
///   scroll animations). All Apple TV scrolling is owned by `tvReveal`.
/// - Any other re-entrant semantics action arriving during
///   `SchedulerPhase.persistentCallbacks` is deferred to a post-frame callback
///   so it runs after `flushSemantics()` completes.
@visibleForTesting
void installAppleTvSemanticsGuard({
  ui.PlatformDispatcher? dispatcher,
  SchedulerBinding? scheduler,
}) {
  final pd = dispatcher ?? WidgetsBinding.instance.platformDispatcher;
  final sb = scheduler ?? SchedulerBinding.instance;
  final original = pd.onSemanticsActionEvent;
  if (original == null) return;
  pd.onSemanticsActionEvent = (event) {
    if (event.type == ui.SemanticsAction.scrollToOffset) return;
    if (sb.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      sb.addPostFrameCallback((_) => original(event));
      return;
    }
    original(event);
  };
}

/// No-op [Downloader] used on Apple TV where offline downloads are disabled,
/// preventing `background_downloader` (and its `connectivity_plus` plugin
/// channels) from ever being instantiated.
@visibleForTesting
class TvosNoopDownloader implements Downloader {
  const TvosNoopDownloader();

  @override
  Stream<DownloaderEvent> get events => const Stream.empty();

  @override
  Stream<String> get notificationTaps => const Stream.empty();

  @override
  Future<void> start({String? partialDir, int maxRunning = 2}) async {}

  @override
  Future<void> setNotices(DownloadNotices notices) async {}

  @override
  Future<void> askToNotify() async {}

  @override
  Future<void> askForStorage() async {}

  @override
  Future<bool> enqueue(DownloadJob job) async => false;

  @override
  Future<bool> pause(String taskId) async => false;

  @override
  Future<bool> resume(
    String taskId,
    String url, {
    DownloadTaskNotice? notice,
  }) async => false;

  @override
  Future<void> cancel(String taskId) async {}

  @override
  Future<bool> canResume(String taskId) async => false;

  @override
  Future<void> sync() async {}

  @override
  Future<Map<String, KnownTask>> known() async => const {};

  @override
  Future<List<String>> tempDirs() async => const [];

  @override
  Future<Map<String, String>> protectedTempFiles(Set<String> taskIds) async =>
      const {};

  @override
  Future<String> pathOf(FileSpot spot) async =>
      p.join(spot.directory, spot.fileName);
}

QueryExecutor _openTvosDatabase() => LazyDatabase(() async {
  final cacheDir = await getApplicationCacheDirectory();
  final dbDir = Directory(p.join(cacheDir.path, 'db'));
  if (!dbDir.existsSync()) dbDir.createSync(recursive: true);
  return NativeDatabase.createInBackground(
    File(p.join(dbDir.path, 'cinemakom.sqlite')),
  );
});

String _dropBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;
