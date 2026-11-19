import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/features/details/details_screen.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';
import '../../repositories/fake_api_client.dart';
import 'fake_engine.dart';

/// Details of the fixture movie, then Play.
Future<void> openMovie(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push('/home/title/3119279');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play'));
  // The player shows a BulbLoader while it opens: no pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('Play opens the player full screen, and back returns', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(engine.opened.single.source.uri, contains('cdn.shabakaty.com'));

    engine.emitReady();
    await tester.pump();
    // Title, the quality chip (Settings: 1080p) and the subtitle chip.
    expect(find.text('Eve of Destruction'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(PlayerScreen),
        matching: find.byTooltip('Back'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(engine.disposed, isTrue);
  });

  testWidgets('controls hide while playing and come back on tap', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady();
    await tester.pump();

    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(PlayerScreen),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(), 0);

    await tester.tapAt(const Offset(422, 195));
    await tester.pump();
    expect(opacity(), 1);

    // Paused: the controls stay.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 5));
    expect(opacity(), 1);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('the quality menu switches at the current position', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady(at: const Duration(minutes: 3));
    await tester.pump();

    await tester.tap(find.text('1080p'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('720p').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.opened, hasLength(2));
    expect(engine.opened.last.start, const Duration(minutes: 3));
  });

  testWidgets('a title without streams says so, with Try again', (
    tester,
  ) async {
    await pumpApp(
      tester,
      width: 844,
      height: 390,
      api: fixtureApi([FakeApiClient.path('transcoddedFiles/', <Object?>[])]),
    );
    await openMovie(tester);
    expect(find.text("This video isn't available right now."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('in Arabic the top bar flips but the seek bar stays LTR', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(
      tester,
      engine: engine,
      width: 844,
      height: 390,
      store: MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
    );
    ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
        .read(routerProvider)
        .push('/home/title/3119279');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitReady();
    await tester.pump();

    expect(directionAt(tester, find.byType(PlayerScreen)), TextDirection.rtl);
    final bar = find.byType(SeekBar);
    expect(
      Directionality.of(
        tester.element(
          find.descendant(of: bar, matching: find.byType(CustomPaint)),
        ),
      ),
      TextDirection.ltr,
    );
    // Back sits at the start edge: the right side in RTL.
    final back = tester.getCenter(find.byIcon(Icons.arrow_back));
    expect(back.dx, greaterThan(844 / 2));
  });
}
