import 'dart:async';
import 'dart:ui' as ui;

import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/core/platform/platform_info.dart';
import 'package:cinemakom/core/player/av_player_engine.dart';
import 'package:cinemakom/core/player/player_engine.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/main_tvos.dart';
import 'package:cinemakom/tv/focus/tv_back.dart';
import 'package:cinemakom/tv/theme/tv_space.dart';
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/widgets/tv_downloads.dart';
import 'package:cinemakom/tv/widgets/tv_text_entry.dart';
import 'package:flutter/scheduler.dart';
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

  test(
    'Apple TV platform flags isolate capabilities without affecting defaults',
    () {
      expect(isAppleTv, isFalse);
      expect(supportsDownloads, isTrue);

      debugIsAppleTvOverride = true;
      expect(isAppleTv, isTrue);
      expect(isTv, isTrue);
      expect(isTouchMobile, isFalse);
      expect(supportsDownloads, isFalse);
    },
  );

  testWidgets(
    'Apple TV hides Downloads tab and scales 1920x1080 4K to 960x540',
    (tester) async {
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
    },
  );

  testWidgets(
    'Apple TV Menu/Back at Home root yields to tvOS instead of popping',
    (tester) async {
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
    },
  );

  testWidgets(
    'Apple TV Details hides download controls with no focus traps (EN & AR)',
    (tester) async {
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
              find
                  .text(lang == 'ar' ? 'الرئيسية' : 'Home')
                  .evaluate()
                  .isNotEmpty,
          backChecks: 6,
        );
        expect(find.byType(TvMovieDownloadButton), findsNothing);
        expect(find.byType(TvEpisodeDownloadButton), findsNothing);
      }
    },
  );

  testWidgets(
    'Apple TV semantics guard drops all scrollToOffset and defers other actions during persistentCallbacks',
    (tester) async {
      final received = <ui.SemanticsAction>[];
      final pd = tester.binding.platformDispatcher;
      final savedHandler = pd.onSemanticsActionEvent;
      addTearDown(() => pd.onSemanticsActionEvent = savedHandler);

      pd.onSemanticsActionEvent = (event) => received.add(event.type);
      installAppleTvSemanticsGuard(dispatcher: pd, scheduler: tester.binding);

      // Even outside persistentCallbacks (idle), scrollToOffset from UIKit's
      // UIScrollView bridge is dropped so it never fights tvReveal; other
      // semantics actions (e.g. tap) pass straight through.
      pd.onSemanticsActionEvent!(
        const ui.SemanticsActionEvent(
          type: ui.SemanticsAction.scrollToOffset,
          viewId: 0,
          nodeId: 1,
        ),
      );
      expect(received, isEmpty);
      pd.onSemanticsActionEvent!(
        const ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          viewId: 0,
          nodeId: 1,
        ),
      );
      expect(received, [ui.SemanticsAction.tap]);
      received.clear();

      // Simulate re-entrant semantics actions fired inside drawFrame /
      // flushSemantics (SchedulerPhase.persistentCallbacks).
      var ranPersistent = false;
      tester.binding.addPersistentFrameCallback((_) {
        if (ranPersistent) return;
        ranPersistent = true;
        expect(
          tester.binding.schedulerPhase,
          SchedulerPhase.persistentCallbacks,
        );
        pd.onSemanticsActionEvent!(
          const ui.SemanticsActionEvent(
            type: ui.SemanticsAction.scrollToOffset,
            viewId: 0,
            nodeId: 1,
          ),
        );
        pd.onSemanticsActionEvent!(
          const ui.SemanticsActionEvent(
            type: ui.SemanticsAction.tap,
            viewId: 0,
            nodeId: 2,
          ),
        );
        // Neither ran synchronously inside flushSemantics.
        expect(received, isEmpty);
      });

      await tester.pumpWidget(const SizedBox());
      // scrollToOffset was dropped; tap ran in the post-frame callback.
      expect(ranPersistent, isTrue);
      expect(received, [ui.SemanticsAction.tap]);
    },
  );

  test(
    'AppleTvPathProvider redirects support and documents directories to caches',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
              calls.add(call.method);
              if (call.method == 'getApplicationCacheDirectory') {
                return '/var/mobile/Containers/Data/Application/Library/Caches';
              }
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );

      installAppleTvPathProvider();
      final provider = AppleTvPathProvider();
      expect(
        await provider.getApplicationSupportPath(),
        '/var/mobile/Containers/Data/Application/Library/Caches',
      );
      expect(
        await provider.getApplicationDocumentsPath(),
        '/var/mobile/Containers/Data/Application/Library/Caches',
      );
      expect(calls, [
        'getApplicationCacheDirectory',
        'getApplicationCacheDirectory',
      ]);
    },
  );

  test(
    'TvosNoopDownloader completes without touching platform channels',
    () async {
      const noop = TvosNoopDownloader();
      await noop.start();
      await noop.askToNotify();
      expect(await noop.known(), isEmpty);
      expect(await noop.pause('1'), isFalse);
      expect(await noop.resume('1', 'https://example.com'), isFalse);
      expect(
        await noop.pathOf(
          const FileSpot('applicationSupport', 'Downloads', 'a.mp4'),
        ),
        'Downloads/a.mp4',
      );
    },
  );

  testWidgets('Search bar focus ring has clearance inside its scroll view', (
    tester,
  ) async {
    debugIsAppleTvOverride = true;
    await pumpApp(tester, tv: true);
    final tv = TvDriver(tester);
    await tv.up();
    await tv.right(); // Search tab
    await tv.down(); // Search box
    expect(tv.focused, 'Titles, actors, directors');

    final scrollTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final boxTop = tester.getTopLeft(find.byType(TvTextEntry)).dy;
    expect(
      boxTop - scrollTop,
      greaterThanOrEqualTo(TvFocusStyle.buttonGap + TvFocusStyle.ring),
    );

    // Apple TV uses ClampingScrollPhysics (matching Android TV) rather than
    // iOS's default BouncingScrollPhysics.
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets(
    'AvPlayerEngine drives native HDR platform view, reuses session, tracks HDR and preserves position on error',
    (tester) async {
      final calls = <MethodCall>[];
      var nextId = 41;
      const methodChannel = MethodChannel(AvPlayerEngine.methodChannelName);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        if (call.method == 'create') return ++nextId;
        return null;
      });
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(methodChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });

      final eventControllers = <int, StreamController<dynamic>>{};
      final engine = AvPlayerEngine(
        loadText: (_) async => '1\n00:00:01,000 --> 00:00:05,000\nمرحباً\n',
        eventChannelFactory: (id) {
          final controller = eventControllers.putIfAbsent(
            id,
            () => StreamController<dynamic>.broadcast(),
          );
          return _FakeEventChannel(controller.stream);
        },
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          await engine.dispose();
          for (final c in eventControllers.values) {
            await c.close();
          }
        });
      });

      final errors = <String>[];
      final ratios = <double>[];
      final subtitles = <List<String>>[];
      engine.errors.listen(errors.add);
      engine.aspectRatio.listen(ratios.add);
      engine.subtitleText.listen(subtitles.add);

      await tester.runAsync(
        () => engine.open(
          const EngineSource(
            'https://cdn.example/movie_4k_hdr.mp4',
            headers: {'Referer': 'https://cinemana.shabakaty.com/'},
          ),
          start: const Duration(seconds: 12),
        ),
      );

      expect(calls.map((c) => c.method).toList(), ['create', 'open']);
      final openArgs = calls[1].arguments as Map<Object?, Object?>;
      expect(openArgs['playerId'], 42);
      expect(openArgs['uri'], 'https://cdn.example/movie_4k_hdr.mp4');
      expect(openArgs['headers'], {
        'Referer': 'https://cinemana.shabakaty.com/',
      });
      expect(openArgs['startMs'], 12000);
      expect(openArgs['fit'], 'contain');

      // Native platform view renders AVPlayerLayer directly (no texture view).
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: engine.buildVideo(fit: BoxFit.cover),
        ),
      );
      await tester.runAsync(() async {});
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, AvPlayerEngine.viewType);
      expect(view.creationParams, {'playerId': 42, 'fit': 'cover'});
      expect(calls.last.method, 'setFit');
      expect((calls.last.arguments as Map<Object?, Object?>)['fit'], 'cover');

      // Native events update HDR format, aspect ratio, position, subtitles, and
      // keep last known position/duration intact when a fatal stream error hits.
      await tester.runAsync(
        () => engine.setSubtitle(
          const EngineSubtitle(
            uri: 'https://cdn.example/ar.srt',
            language: 'ar',
          ),
        ),
      );
      final events = eventControllers[42]!;
      await tester.runAsync(() async {
        events.add({'type': 'hdr', 'format': 'dolbyVision'});
        events.add({'type': 'duration', 'ms': 7200000});
        events.add({'type': 'size', 'width': 3840, 'height': 1600});
        events.add({'type': 'position', 'ms': 2500});
        events.add({'type': 'error', 'message': 'Failed to load video: 403'});
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(engine.hdrFormat.value, 'dolbyVision');
      expect(engine.currentPosition, const Duration(milliseconds: 2500));
      expect(engine.currentDuration, const Duration(milliseconds: 7200000));
      expect(ratios, [closeTo(2.4, 0.001)]);
      expect(subtitles.last, ['مرحباً']);
      expect(errors, ['Failed to load video: 403']);

      // Reopening (quality / episode switch) reuses the same native HDR player.
      calls.clear();
      await tester.runAsync(
        () => engine.open(const EngineSource('https://cdn.example/next.mp4')),
      );
      expect(calls.map((c) => c.method).toList(), ['open']);
      expect((calls.single.arguments as Map<Object?, Object?>)['playerId'], 42);

      // Disposing tears down the native session and resets display criteria.
      await tester.pumpWidget(const SizedBox());
      calls.clear();
      await tester.runAsync(() => engine.dispose());
      expect(calls.map((c) => c.method).toList(), ['dispose']);
      expect((calls.single.arguments as Map<Object?, Object?>)['playerId'], 42);
    },
  );
}

class _FakeEventChannel extends EventChannel {
  _FakeEventChannel(this._stream) : super('fake');

  final Stream<dynamic> _stream;

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) => _stream;
}
