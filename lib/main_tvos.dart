import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/network/api_providers.dart';
import 'core/platform/platform_info.dart';
import 'core/player/av_player_engine.dart';
import 'core/storage/database.dart';
import 'data/repositories/library_repository.dart';
import 'features/player/player_controller.dart';
import 'main.dart' show noRetry, registerFontLicenses;
import 'tv/tv_app.dart';

/// Dedicated Apple TV (tvOS) entrypoint.
///
/// Kept completely separate from `lib/main.dart` so Android, iOS, macOS,
/// Linux, and Windows builds remain untouched:
/// - Does not initialize `media_kit`, `sqflite_common_ffi`, `window_manager`,
///   or mobile orientation locks.
/// - Disables offline downloads (`supportsDownloads == false`) per tvOS's
///   purgeable-storage rules.
/// - Stores the Drift SQLite database under `Library/Caches` (safe on tvOS).
/// - Uses [AvPlayerEngine] (`video_player` + `video_player_tvos`) for native
///   4K hardware video decoding.
Future<void> main() async {
  markAppleTv();
  WidgetsFlutterBinding.ensureInitialized();
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
