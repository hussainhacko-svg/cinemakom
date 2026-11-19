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
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' show Icons, Scrollable, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';

final _dir = Directory(
  Platform.isAndroid || Platform.isIOS
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
  Size size,
) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [preferenceStoreProvider.overrideWith((ref) => store)],
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
