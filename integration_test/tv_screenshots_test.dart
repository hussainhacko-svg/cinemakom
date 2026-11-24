// Drives the TV UI (lib/tv) with the remote's keys at 960 × 540 dp ×2, the
// TCL's canvas, on the live API with real fonts, and saves a PNG of each
// screen for design review against the TV artboards (docs/TV.md TV-6):
//
//   fvm flutter test integration_test/tv_screenshots_test.dart -d linux
//
// The PNGs go to $SCREENSHOT_DIR (default build/screenshots), named tv-*.
// The player plays a real stream (media_kit on Linux).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import '../test/tv/tv_driver.dart';

final _dir = Directory(
  Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots',
)..createSync(recursive: true);

/// Lets real time pass (live API calls, images, the stream) while pumping.
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
    final image = await layer.toImage(
      Offset.zero & (view.size * tester.view.devicePixelRatio),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${_dir.path}/tv-$name.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// One press of a remote key, then a moment for focus and scrolling.
Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await _wait(tester, 300);
  }
}

/// Seek steps, quicker than the player's 600 ms settle, then the shot
/// while the seek is still pending.
Future<void> _seek(WidgetTester tester, String name, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.sendKeyEvent(_right);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
  await _shot(tester, name, wait: 0);
}

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
// Enter: Linux has no Select key (the remote's OK).
const _ok = LogicalKeyboardKey.enter;
const _back = LogicalKeyboardKey.escape;

const _min = Duration(minutes: 1);

Future<void> _pump(WidgetTester tester, {required bool arabic}) async {
  tester.view
    ..physicalSize = const Size(960, 540) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [
        preferenceStoreProvider.overrideWith(
          (ref) => MemoryPreferenceStore({
            PreferenceKeys.language: arabic ? 'ar' : 'en',
            PreferenceKeys.searchHistory: '["dune","friends"]',
          }),
        ),
        libraryRepositoryProvider.overrideWithValue(
          MemoryLibraryRepository([
            WatchProgress(
              videoId: '4401',
              seriesId: '4328',
              season: 2,
              episode: 1,
              position: _min * 10,
              duration: _min * 22,
              updatedAt: DateTime(2026, 11, 20, 12),
              title: const LocalizedText(en: 'Friends'),
              kind: VideoKind.series,
            ),
          ]),
        ),
      ],
      child: const TvApp(),
    ),
  );
  await _wait(tester, 500);
}

void _push(WidgetTester tester, String location, {Object? extra}) =>
    ProviderScope.containerOf(tester.element(find.byType(TvApp)))
        .read(tvRouterProvider)
        .push(location, extra: extra);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  for (final arabic in [false, true]) {
    final l = arabic ? 'ar' : 'en';
    // The tabs run along the reading direction (R12).
    final along = arabic ? _left : _right;

    testWidgets('TV screens ($l)', (tester) async {
      await _pump(tester, arabic: arabic);
      await _shot(tester, '$l-01-home', wait: 7000);
      await _key(tester, _down, times: 2);
      await _shot(tester, '$l-02-home-rows', wait: 3000);

      _push(tester, '/home/title/4328'); // Friends
      await _shot(tester, '$l-03-details-series', wait: 5000);
      await _key(tester, _down);
      await _shot(tester, '$l-04-details-episodes', wait: 2000);
      await _key(tester, _back);

      // The tabs, by remote.
      await _key(tester, _up, times: 3);
      await _key(tester, along);
      await _key(tester, _down);
      await _shot(tester, '$l-05-search', wait: 3000);
      await _key(tester, _up);
      await _key(tester, along);
      await _key(tester, _down);
      await _shot(tester, '$l-06-library', wait: 3000);
      await _key(tester, _up);
      await _key(tester, along);
      await _key(tester, _down);
      await _shot(tester, '$l-07-downloads');
      await _key(tester, _up);
      await _key(tester, along);
      await _key(tester, _down);
      await _shot(tester, '$l-08-settings');
      await _key(tester, _ok);
      await _shot(tester, '$l-09-settings-language-panel', wait: 1000);
      await _key(tester, _back);
      // Settings → Help → Activity log, then its QR code (the real server,
      // on this machine's Wi-Fi, closed with the panel).
      await _key(tester, _down, times: 6);
      await _key(tester, _ok);
      await _shot(tester, '$l-09b-activity-log', wait: 1000);
      await _key(tester, _ok);
      await _shot(tester, '$l-09c-activity-log-phone', wait: 1500);
      await _key(tester, _back);
      await _key(tester, _back);

      // The player on a live stream: controls, a seek, a panel.
      _push(
        tester,
        '/watch/4401',
        extra: const PlaybackRequest(
          item: MediaItem(
            id: '4328',
            title: LocalizedText(en: 'Friends'),
            kind: VideoKind.series,
          ),
          episodeId: '4401',
        ),
      );
      await _wait(tester, 8000);
      final tv = TvDriver(tester);
      await tv.focusLabel(arabic ? 'إيقاف مؤقت' : 'Pause');
      await _key(tester, _ok); // pause, so the controls stay
      await _shot(tester, '$l-10-player-controls', wait: 1500);
      await tv.focusLabel(arabic ? 'موضع التشغيل' : 'Playback position');
      await _seek(tester, '$l-11-player-seek-bar', 3);
      // Down leaves the bar, seeking or not (taking the shot can outlast the
      // 600 ms settle).
      await _key(tester, _down);
      await tv.focusLabel(
        arabic ? 'السرعة: \u20661×\u2069' : 'Speed: \u20661×\u2069',
      );
      await _key(tester, _ok);
      await _shot(tester, '$l-12-player-panel', wait: 1000);
      await _key(tester, _back); // close the panel
      await _key(tester, _back); // hide the controls
      await _seek(tester, '$l-13-player-watching-seek', 2);
      await _wait(tester, 1000); // the seek settles
      await _key(tester, _back); // leave
      await _wait(tester, 1000);
    });
  }
}
