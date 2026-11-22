// Drives the real app (real fonts, real rendering) through the shell
// screens and saves a PNG of each, for design review:
//
//   fvm flutter test integration_test/screenshots_test.dart -d linux
//
// On desktop the PNGs go to $SCREENSHOT_DIR (default build/screenshots).
// On Android they go to the app's cache folder; pull them with
//   adb exec-out run-as io.github.sharon_xa.cinemakom \
//     tar -C cache/screenshots -c . | tar -x -C <folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/data/repositories/downloads_repository.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' show Icons, Scrollable, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';

import '../test/helpers/fake_downloader.dart';

final _dir = Directory(
  Platform.isAndroid
      ? '${Directory.systemTemp.path}/screenshots'
      : Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots',
)..createSync(recursive: true);

/// Lets real time pass (live API calls, images) while pumping frames.
/// pumpAndSettle can't be used: the bulb loader animates while loading.
Future<void> _wait(WidgetTester tester, [int ms = 2500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
}

Future<void> _shot(WidgetTester tester, String name, {int wait = 2500}) async {
  await _wait(tester, wait);
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    // The root layer already scales by the device pixel ratio, so capture
    // its physical-pixel bounds at ratio 1.
    final image = await layer.toImage(
      Offset.zero & (view.size * tester.view.devicePixelRatio),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${_dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _pump(
  WidgetTester tester,
  MemoryPreferenceStore store,
  Size size, {
  LibraryRepository? library,
  DownloadStore? downloads,
  Downloader? downloader,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [
        preferenceStoreProvider.overrideWith((ref) => store),
        if (library != null)
          libraryRepositoryProvider.overrideWithValue(library),
        if (downloads != null)
          downloadStoreProvider.overrideWithValue(downloads),
        if (downloader != null)
          downloaderProvider.overrideWithValue(downloader),
      ],
      child: const CinemakomApp(),
    ),
  );
  await _wait(tester, 500);
}

/// Pushes [location] on the current tab, as tapping a list item would.
Future<void> _push(WidgetTester tester, String location) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push(location);
  await _wait(tester, 500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  const phone = Size(390, 844);

  testWidgets('phone: first launch, tabs, settings, Arabic', (tester) async {
    await _pump(tester, MemoryPreferenceStore(), phone);
    await _shot(tester, '01-phone-language-en');

    await tester.tap(find.text('العربية'));
    await _shot(tester, '02-phone-language-ar-preview');
    await tester.tap(find.text('English'));
    await _wait(tester, 500);
    await tester.tap(find.text('Continue'));
    await _shot(tester, '03-phone-home');

    await tester.tap(find.text('Library'));
    await _shot(tester, '04-phone-library');
    await tester.tap(find.text('Settings'));
    await _shot(tester, '05-phone-settings');

    await tester.tap(find.text('Default quality'));
    await _shot(tester, '06-phone-quality-sheet');
    await tester.tap(find.text('2160p · 4K'));
    await _wait(tester, 500);

    await tester.tap(find.text('Language'));
    await _wait(tester, 500);
    await tester.tap(find.text('العربية').last);
    await _shot(tester, '07-phone-settings-ar');
    await tester.tap(find.text('الرئيسية'));
    await _shot(tester, '08-phone-home-ar');
  });

  testWidgets('tablet: rail', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      const Size(900, 700),
    );
    await tester.tap(find.text('Settings'));
    await _shot(tester, '09-tablet-settings-rail');
  });

  testWidgets('desktop: extended rail, dialog picker, Arabic', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      const Size(1280, 800),
    );
    await _shot(tester, '10-desktop-home');
    await tester.tap(find.text('Settings'));
    await _shot(tester, '11-desktop-settings');
    await tester.tap(find.text('Default subtitles'));
    await _shot(tester, '12-desktop-subtitle-dialog');
    await tester.tapAt(const Offset(20, 20));
    await _wait(tester, 500);
    await tester.tap(find.text('Language'));
    await _wait(tester, 500);
    await tester.tap(find.text('العربية').last);
    await _shot(tester, '13-desktop-settings-ar');
  });

  testWidgets('phone: browsing with live data', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      phone,
    );
    await _shot(tester, '20-phone-home-live', wait: 6000);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await _shot(tester, '21-phone-home-rows', wait: 4000);

    // Details of the first banner (the hero's Play opens it until Phase 4).
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await _wait(tester, 500);
    await tester.tap(find.text('Play').first);
    await _shot(tester, '22-phone-details-hero', wait: 5000);
    await tester.tap(find.byTooltip('Back'));
    await _wait(tester, 500);

    await _push(tester, '/home/title/4328'); // Friends
    await _shot(tester, '23-phone-details-series', wait: 5000);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await _shot(tester, '24-phone-details-episodes', wait: 3000);
    await _push(tester, '/home/person/627'); // Jennifer Aniston
    await _shot(tester, '28-phone-person', wait: 5000);

    await tester.tap(find.text('Search'));
    await _wait(tester, 2000);
    await _shot(tester, '25-phone-search-empty');
    await tester.enterText(find.byType(TextField), 'batman');
    await _shot(tester, '26-phone-search-results', wait: 6000);
    await tester.tap(find.byTooltip('Clear search'));
    await _wait(tester, 2000);
    await tester.tap(find.text('Action').first);
    await _shot(tester, '27-phone-genre', wait: 6000);
  });

  // A library in memory (never the real database), refreshed from the API.
  MemoryLibraryRepository savedLibrary() {
    const min = Duration(minutes: 1);
    final now = DateTime.now();
    return MemoryLibraryRepository(
      [
        // Friends S1E1 finished: Up next is S1E2.
        WatchProgress(
          videoId: '4328',
          seriesId: '4328',
          season: 1,
          episode: 1,
          position: min * 22,
          duration: min * 22,
          updatedAt: now,
          title: const LocalizedText(en: 'Friends'),
          kind: VideoKind.series,
        ),
        WatchProgress(
          videoId: '3119279',
          position: min * 86,
          duration: min * 100,
          updatedAt: now.subtract(const Duration(hours: 1)),
          title: const LocalizedText(en: 'Eve of Destruction'),
          kind: VideoKind.movies,
        ),
      ],
      const [
        MediaItem(id: '3157703'),
        MediaItem(id: '4328', kind: VideoKind.series),
        MediaItem(id: '3119279'),
      ],
    );
  }

  testWidgets('phone: library with saved titles', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      phone,
      library: savedLibrary(),
    );
    await _wait(tester, 2000);
    await tester.tap(find.text('Library'));
    await _shot(tester, '60-phone-library-continue', wait: 5000);
    await tester.tap(find.text('Favorites'));
    await _shot(tester, '61-phone-library-favorites', wait: 4000);
    await tester.tap(find.text('Home'));
    await _wait(tester, 1000);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await _shot(tester, '62-phone-home-continue', wait: 3000);
  });

  testWidgets('desktop: library', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      const Size(1280, 800),
      library: savedLibrary(),
    );
    await _wait(tester, 2000);
    await tester.tap(find.text('Library'));
    await _shot(tester, '65-desktop-library-continue', wait: 5000);
    await tester.tap(find.text('Favorites'));
    await _shot(tester, '66-desktop-library-favorites', wait: 4000);
  });

  testWidgets('phone: library in Arabic', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
      phone,
      library: savedLibrary(),
    );
    await _wait(tester, 2000);
    await tester.tap(find.text('مكتبتي'));
    await _shot(tester, '63-phone-library-continue-ar', wait: 5000);
    await _push(tester, '/library/title/3119279');
    await _shot(tester, '64-phone-details-favorite-ar', wait: 4000);
  });

  // Downloads in memory, with a fake engine that reports progress.
  (MemoryDownloadStore, FakeDownloader) savedDownloads() {
    const gb = 1024 * 1024 * 1024;
    const poster = 'https://cnth2.shabakaty.com/vascin-poster-images/';
    Download row(
      String id,
      String title,
      String image, {
      String? titleId,
      DownloadStatus status = DownloadStatus.complete,
      int? season,
      int? episode,
      int bytes = 2 * gb,
      DownloadProblem? problem,
      String quality = '1080p',
    }) => Download(
      videoId: id,
      titleId: titleId ?? id,
      title: LocalizedText(en: title),
      posterUrl: '$poster$image',
      season: season,
      episode: episode,
      kind: season == null ? VideoKind.movies : VideoKind.series,
      quality: quality,
      baseDirectory: 'root',
      directory: Directory.systemTemp.path,
      fileName: '$id.mp4',
      status: status,
      problem: problem,
      totalBytes: bytes,
      addedAt: DateTime(2026, 11, 19),
    );
    const friends =
        '571730E3-AF79-2C62-E85F-968A41836EAC_poster_medium_thumb.jpg';
    final store = MemoryDownloadStore([
      row(
        '3157703',
        'The Beast',
        'EC21480E-8A60-E47C-05A8-1C2FC08888DC_poster_medium_thumb.jpg',
        status: DownloadStatus.running,
        bytes: 3 * gb,
      ),
      row(
        '3158531',
        'Heartland',
        '5F822ED6-2C66-ADCB-8B9C-12AE905FAAAE_poster_medium_thumb.jpg',
        status: DownloadStatus.failed,
        problem: DownloadProblem.noSpace,
      ),
      row(
        '3119279',
        'Eve of Destruction',
        '4E5E5E90-65C3-D435-FEF5-F40D6D3A7BE4_poster_medium_thumb.jpg',
        quality: '720p',
        bytes: 283327732,
      ),
      for (var e = 1; e <= 3; e++)
        row(
          'f$e',
          'Friends',
          friends,
          titleId: '4328',
          season: 1,
          episode: e,
          bytes: 94415700,
          quality: '360p',
        ),
    ]);
    final downloader = FakeDownloader()
      ..knownStates['3157703'] = DownloaderState.running;
    return (store, downloader);
  }

  const beastProgress = DownloaderProgress(
    '3157703',
    fraction: 0.42,
    bytesPerSecond: 4.3 * 1024 * 1024,
    timeLeft: Duration(minutes: 7),
  );

  testWidgets('phone: downloads', (tester) async {
    final (store, downloader) = savedDownloads();
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      phone,
      downloads: store,
      downloader: downloader,
    );
    await _wait(tester, 1500);
    downloader.send(beastProgress);
    await tester.tap(find.text('Downloads'));
    await _shot(tester, '70-phone-downloads', wait: 4000);
    await tester.tap(find.text('Friends'));
    await _shot(tester, '71-phone-downloads-series', wait: 3000);
    await _push(tester, '/downloads/title/4328');
    await _wait(tester, 4000);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await _shot(tester, '72-phone-details-episodes-download', wait: 3000);
    await _push(tester, '/downloads/title/3158531');
    await _shot(tester, '73-phone-details-movie-download', wait: 4000);
  });

  testWidgets('phone: downloads in Arabic', (tester) async {
    final (store, downloader) = savedDownloads();
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
      phone,
      downloads: store,
      downloader: downloader,
    );
    await _wait(tester, 1500);
    downloader.send(beastProgress);
    await tester.tap(find.text('التنزيلات'));
    await _shot(tester, '74-phone-downloads-ar', wait: 4000);
  });

  testWidgets('desktop: browsing with live data', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      const Size(1280, 800),
    );
    await _shot(tester, '30-desktop-home-live', wait: 6000);
    await _push(tester, '/home/title/4328');
    await _shot(tester, '31-desktop-details-series', wait: 5000);
  });

  testWidgets('phone: Arabic browsing', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
      phone,
    );
    await _shot(tester, '40-phone-home-ar-live', wait: 6000);
    await _push(tester, '/home/title/4328');
    await _shot(tester, '41-phone-details-ar', wait: 5000);
    await _push(tester, '/home/person/627');
    await _shot(tester, '42-phone-person-ar', wait: 5000);
  });

  testWidgets('desktop: player with live data', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
      const Size(1280, 720),
    );
    await _push(tester, '/home/title/191463');
    await _wait(tester, 4000);
    await tester.tap(find.text('Play').first);
    await _shot(tester, '50-desktop-player', wait: 2000);
    // Jump about 10 minutes in (dialogue), then pause so the controls stay.
    final bar = tester.getRect(find.byType(SeekBar));
    await tester.tapAt(Offset(bar.left + bar.width * 0.07, bar.center.dy));
    await _wait(tester, 4000);
    await tester.tapAt(const Offset(640, 200));
    await _wait(tester, 300);
    if (find.byTooltip('Pause').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Pause'));
    }
    await _shot(tester, '51-desktop-player-paused', wait: 1500);

    // The chip menus are popovers on wide screens (PLAYER.md §8).
    await tester.tap(find.byIcon(Icons.subtitles_outlined));
    await _wait(tester, 500);
    await tester.tap(find.byTooltip('Show subtitles later'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show subtitles later'));
    await _shot(tester, '52-desktop-subtitle-menu', wait: 800);
    await tester.tapAt(const Offset(200, 650));
    await _wait(tester, 500);
    await tester.tap(find.byTooltip('Quality'));
    await _shot(tester, '53-desktop-quality-menu', wait: 800);
  });

  testWidgets('phone landscape: player menus in Arabic', (tester) async {
    await _pump(
      tester,
      MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
      const Size(844, 390),
    );
    await _push(tester, '/home/title/191463');
    await _wait(tester, 4000);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await _wait(tester, 4000);
    await tester.tapAt(const Offset(422, 195));
    await _wait(tester, 300);
    if (find.byIcon(Icons.pause).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.pause));
    }
    await _shot(tester, '54-phone-player-ar', wait: 1000);
    await tester.tap(find.byIcon(Icons.subtitles_outlined));
    await _shot(tester, '55-phone-subtitle-menu-ar', wait: 800);
  });
}
