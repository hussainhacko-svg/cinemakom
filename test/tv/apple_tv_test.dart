import 'package:cinemakom/core/platform/platform_info.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/tv/focus/tv_back.dart';
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/widgets/tv_downloads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';
import 'reachability.dart';
import 'tv_driver.dart';

void main() {
  tearDown(() {
    debugIsAppleTvOverride = null;
    debugIsTvOverride = null;
  });

  test('Apple TV platform flags isolate capabilities without affecting defaults', () {
    expect(isAppleTv, isFalse);
    expect(supportsDownloads, isTrue);

    debugIsAppleTvOverride = true;
    expect(isAppleTv, isTrue);
    expect(isTv, isTrue);
    expect(isTouchMobile, isFalse);
    expect(supportsDownloads, isFalse);
  });

  testWidgets('Apple TV hides Downloads tab and scales 1920x1080 4K to 960x540', (
    tester,
  ) async {
    debugIsAppleTvOverride = true;
    await pumpApp(tester, tv: true);
    // Simulate Apple TV 4K native viewport (1920x1080 pt at 2x = 3840x2160 px).
    tester.view
      ..physicalSize = const Size(3840, 2160)
      ..devicePixelRatio = 2.0;
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Downloads'), findsNothing);

    // Effective DPR becomes 4.0 (2.0 * 2.0), allocating the 250 MB 4K cache.
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 250 << 20);
  });

  testWidgets('Apple TV Menu/Back at Home root yields to tvOS instead of popping', (
    tester,
  ) async {
    debugIsAppleTvOverride = true;
    var systemPopped = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') systemPopped = true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpApp(tester, tv: true);
    final tv = TvDriver(tester);
    // Back from hero Play moves focus to Home tab.
    await tv.back();
    expect(tv.focused, 'Home');

    // Back at Home tab returns false (unhandled) without calling SystemNavigator.pop.
    expect(tvHandleBack(), isFalse);
    expect(systemPopped, isFalse);
  });

  testWidgets('Apple TV Details hides download controls with no focus traps (EN & AR)', (
    tester,
  ) async {
    debugIsAppleTvOverride = true;
    for (final lang in ['en', 'ar']) {
      await expectNoTraps(
        tester,
        pumpScreen: () async {
          await tester.pumpWidget(const SizedBox());
          await pumpApp(
            tester,
            tv: true,
            store: MemoryPreferenceStore({PreferenceKeys.language: lang}),
          );
          final tv = TvDriver(tester);
          // Open the first series/movie card on Home or navigate to Details.
          await tv.down();
          await tv.ok();
        },
        leftScreen: () =>
            find.byType(TvApp).evaluate().isNotEmpty &&
            find.text(lang == 'ar' ? 'الرئيسية' : 'Home').evaluate().isNotEmpty,
        backChecks: 6,
      );
      expect(find.byType(TvMovieDownloadButton), findsNothing);
      expect(find.byType(TvEpisodeDownloadButton), findsNothing);
    }
  });
}
