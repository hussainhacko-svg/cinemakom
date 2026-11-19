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
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final _dir = Directory(
  Platform.isAndroid || Platform.isIOS
      ? '${Directory.systemTemp.path}/screenshots'
      : Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots',
)..createSync(recursive: true);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
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
      overrides: [preferenceStoreProvider.overrideWith((ref) => store)],
      child: const CinemakomApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phone = Size(390, 844);

  testWidgets('phone: first launch, tabs, settings, Arabic', (tester) async {
    await _pump(tester, MemoryPreferenceStore(), phone);
    await _shot(tester, '01-phone-language-en');

    await tester.tap(find.text('العربية'));
    await _shot(tester, '02-phone-language-ar-preview');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await _shot(tester, '03-phone-home');

    await tester.tap(find.text('Library'));
    await _shot(tester, '04-phone-library');
    await tester.tap(find.text('Settings'));
    await _shot(tester, '05-phone-settings');

    await tester.tap(find.text('Default quality'));
    await _shot(tester, '06-phone-quality-sheet');
    await tester.tap(find.text('2160p · 4K'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية').last);
    await _shot(tester, '13-desktop-settings-ar');
  });
}
