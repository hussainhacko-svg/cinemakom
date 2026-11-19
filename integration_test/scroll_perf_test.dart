// Frame timing check of the real app on a device (profile mode, live API):
// Home scrolling, a long poster grid flung deep (new pages and new posters
// decoding) and opening/closing a title page.
//
//   fvm flutter drive --profile --no-dds -d <android-device-id> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_perf_test.dart
//
// The driver prints UI (build) and raster times per scenario against the
// display's frame budget (8.3 ms at 120 Hz).
import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/navigation.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/paging/media_sources.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(int ms) => binding.delayed(Duration(milliseconds: ms));

  Future<void> flings(
    WidgetTester tester,
    Finder scrollable,
    int count, {
    bool back = false,
  }) async {
    for (var i = 0; i < count; i++) {
      final up = !back || i.isEven;
      await tester.fling(scrollable, Offset(0, up ? -900 : 900), 5000);
      await wait(700);
    }
  }

  testWidgets('scrolling and transitions stay within the frame budget', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(retry: noRetry, child: CinemakomApp()),
    );
    // Startup, the first-launch language choice (a fresh install), and
    // Home's first rows.
    await wait(3000);
    final welcome = find.byType(FilledButton);
    if (welcome.evaluate().isNotEmpty) {
      await tester.tap(welcome.first);
    }
    await wait(5000);
    final router = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>)),
    ).read(routerProvider);

    final home = find.byType(CustomScrollView).first;
    await binding.watchPerformance(
      () => flings(tester, home, 8, back: true),
      reportKey: 'home_scroll',
    );

    router.push(
      '${AppRoutes.home}/list',
      extra: const MediaListArgs(title: 'Featured', source: FeaturedSource()),
    );
    await wait(4000);
    final grid = find.byType(CustomScrollView).last;
    await binding.watchPerformance(
      () => flings(tester, grid, 14),
      reportKey: 'grid_fling_deep',
    );
    router.pop();
    await wait(1500);

    await binding.watchPerformance(() async {
      for (var i = 0; i < 4; i++) {
        router.push(
          '${AppRoutes.home}/title/191463',
          extra: const TitleArgs(
            MediaItem(
              id: '191463',
              title: LocalizedText(en: 'Avengers'),
              kind: VideoKind.movies,
            ),
          ),
        );
        await wait(1500);
        router.pop();
        await wait(1000);
      }
    }, reportKey: 'title_open_close');
  });
}
