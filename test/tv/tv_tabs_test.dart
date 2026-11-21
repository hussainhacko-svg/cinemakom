import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/tv/screens/details/tv_details_screen.dart';
import 'package:cinemakom/tv/tv_app.dart';

import '../helpers/app_harness.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// The Search, Library, Downloads and Settings tabs on TV (docs/TV.md TV-5),
// on fixture data, each reached the way the remote does: Up to the tabs,
// along them, Down into the tab.

final _exits = <String>[];
const _min = Duration(minutes: 1);

WatchProgress _movie() => WatchProgress(
  videoId: '3119279',
  position: _min * 40,
  duration: _min * 100,
  updatedAt: DateTime(2026, 11, 19, 12, 2),
  title: const LocalizedText(en: 'Eve of Destruction'),
  kind: VideoKind.movies,
);

WatchProgress _episode() => WatchProgress(
  videoId: '4401',
  seriesId: '4328',
  season: 2,
  episode: 1,
  position: _min * 10,
  duration: _min * 22,
  updatedAt: DateTime(2026, 11, 19, 12, 1),
  title: const LocalizedText(en: 'Friends'),
  kind: VideoKind.series,
);

final _dir = Directory.systemTemp.createTempSync('tv-dl').path;

Download _download(
  String id, {
  String titleId = '3119279',
  String title = 'Eve of Destruction',
  DownloadStatus status = DownloadStatus.complete,
  int? season,
  int? episode,
}) => Download(
  videoId: id,
  titleId: titleId,
  title: LocalizedText(en: title),
  season: season,
  episode: episode,
  kind: season == null ? VideoKind.movies : VideoKind.series,
  quality: '1080p',
  baseDirectory: 'root',
  directory: _dir,
  fileName: '$id.mp4',
  status: status,
  totalBytes: 2 * 1024 * 1024 * 1024,
  addedAt: DateTime(2026, 11, 19),
);

/// The app on TV, then [tab] (1 Search … 4 Settings) by remote.
Future<TvDriver> _openTab(
  WidgetTester tester,
  int tab, {
  bool arabic = false,
  List<String> history = const [],
  MemoryLibraryRepository? library,
  MemoryDownloadStore? downloads,
  int? freeSpace,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  await tester.pumpWidget(const SizedBox());
  await pumpApp(
    tester,
    tv: true,
    library: library,
    downloads: downloads,
    freeSpace: freeSpace,
    store: MemoryPreferenceStore({
      PreferenceKeys.language: arabic ? 'ar' : 'en',
      if (history.isNotEmpty) PreferenceKeys.searchHistory: jsonEncode(history),
    }),
  );
  final tv = TvDriver(tester);
  await tv.up();
  for (var i = 0; i < tab; i++) {
    // The tabs run along the screen's reading direction (R12).
    arabic ? await tv.left() : await tv.right();
  }
  await tv.down();
  return tv;
}

void main() {
  group('Search', () {
    testWidgets('opens on the box; recent searches, Clear all, genres', (
      tester,
    ) async {
      final tv = await _openTab(tester, 1, history: ['dune', 'friends']);
      expect(tv.focused, 'Titles, actors, directors');
      await tv.down();
      expect(tv.focused, 'All');
      await tv.down();
      expect(tv.focused, 'dune');
      await tv.right();
      expect(tv.focused, 'Remove “dune”');
      // Down keeps the cell.
      await tv.down();
      expect(tv.focused, 'Remove “friends”');
      await tv.ok();
      expect(find.text('friends'), findsNothing);
      // Focus moves on to what's left (R7).
      expect(tv.focused, isNot(startsWith('not a TV item')));
    });

    testWidgets('typing searches; a result opens and Back comes back to it', (
      tester,
    ) async {
      final tv = await _openTab(tester, 1);
      await tv.ok();
      await tester.enterText(find.byType(TextField), 'eve');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      // Done: back to the D-pad, on the box.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tv.down();
      await tv.down();
      await tv.right();
      final result = tv.focused;
      await tv.ok();
      expect(find.byType(TvDetailsScreen), findsOneWidget);
      await tv.back();
      expect(find.byType(TvDetailsScreen), findsNothing);
      expect(tv.focused, result);
      // Opening it remembered the search.
      final store = ProviderScope.containerOf(
        tester.element(find.byType(TvApp)),
      ).read(preferenceStoreProvider).requireValue;
      expect(store.getString(PreferenceKeys.searchHistory), contains('eve'));
    });
  });

  group('Library', () {
    testWidgets('Continue rows: resume, Details, Remove; then Favorites', (
      tester,
    ) async {
      final library = MemoryLibraryRepository([_movie(), _episode()]);
      final tv = await _openTab(tester, 2, library: library);
      expect(tv.focused, 'Continue watching');
      await tv.down();
      expect(tv.focused, startsWith('Eve of Destruction'));
      await tv.right();
      expect(tv.focused, 'Details');
      await tv.right();
      expect(tv.focused, 'Remove');
      await tv.ok();
      // The movie is gone; focus is on the row that moved up.
      expect(find.textContaining('Eve of Destruction'), findsNothing);
      expect(tv.focused, 'Remove');
      await tv.left();
      await tv.left();
      expect(tv.focused, startsWith('Friends'));

      await tv.up();
      await tv.right();
      expect(tv.focused, 'Favorites');
      expect(
        find.text('Pick Favorite on any title to keep it here.'),
        findsOneWidget,
      );
    });
  });

  group('Downloads', () {
    testWidgets('empty: says so, and Browse Home goes Home', (tester) async {
      final tv = await _openTab(tester, 3);
      expect(tv.focused, 'Browse Home');
      await tv.ok();
      expect(tv.focused, anyOf('Home', 'Play'));
    });

    testWidgets('a movie and a series; the series opens its episodes', (
      tester,
    ) async {
      final store = MemoryDownloadStore([
        _download('3119279'),
        _download(
          '4401',
          titleId: '4328',
          title: 'Friends',
          season: 2,
          episode: 1,
        ),
        _download(
          '4402',
          titleId: '4328',
          title: 'Friends',
          season: 3,
          episode: 1,
        ),
      ]);
      final tv = await _openTab(
        tester,
        3,
        downloads: store,
        freeSpace: 3 * 1024 * 1024 * 1024,
      );
      expect(find.textContaining('free on this TV'), findsOneWidget);
      expect(tv.focused, anyOf(startsWith('Eve'), startsWith('Friends')));
      // To the series' row, then its episodes.
      for (var i = 0; i < 2 && !tv.focused.startsWith('Friends'); i++) {
        await tv.down();
      }
      expect(tv.focused, contains('2 episodes'));
      await tv.ok();
      expect(tv.focused, startsWith('Season 2 · Episode 1'));
      await tv.right();
      expect(tv.focused, 'Delete');
      await tv.ok();
      // Asks first, on the safe answer.
      expect(tv.focused, 'Keep it');
      await tv.back();
      expect(tv.focused, 'Delete');
      // Back to the row that opened the page (R2).
      await tv.back();
      expect(tv.focused, contains('2 episodes'));
    });
  });

  group('Settings', () {
    testWidgets('Arabic in place, focus kept on the Language row', (
      tester,
    ) async {
      final tv = await _openTab(tester, 4);
      expect(tv.focused, 'Language, English');
      await tv.ok();
      expect(tv.focused, 'English');
      await tv.down();
      await tv.ok();
      expect(tv.focused, 'اللغة, العربية');
      expect(
        Directionality.of(tester.element(find.text('اللغة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('a value panel opens on the current choice', (tester) async {
      final tv = await _openTab(tester, 4);
      await tv.down();
      expect(tv.focused, startsWith('Theme'));
      await tv.down();
      expect(tv.focused, startsWith('Default quality'));
      await tv.ok();
      expect(tv.focused, '1080p');
      await tv.back();
      expect(tv.focused, startsWith('Default quality'));
    });

    testWidgets('About and licenses lists the packages; Back returns', (
      tester,
    ) async {
      final tv = await _openTab(tester, 4);
      await tv.focusLabel('About and licenses');
      await tv.ok();
      expect(find.text('ABOUT AND LICENSES'), findsOneWidget);
      await tv.back();
      expect(tv.focused, 'About and licenses');
    });
  });

  for (final arabic in [false, true]) {
    final lang = arabic ? 'Arabic' : 'English';
    for (final (tab, name) in [
      (1, 'Search'),
      (2, 'Library'),
      (3, 'Downloads'),
      (4, 'Settings'),
    ]) {
      testWidgets('no traps in $name ($lang)', (tester) async {
        await expectNoTraps(
          tester,
          pumpScreen: () => _openTab(
            tester,
            tab,
            arabic: arabic,
            history: const ['dune'],
            library: MemoryLibraryRepository([_movie(), _episode()]),
            downloads: MemoryDownloadStore([
              _download('3119279'),
              _download(
                '4401',
                titleId: '4328',
                title: 'Friends',
                season: 2,
                episode: 1,
              ),
            ]),
          ),
          leftScreen: () => _exits.isNotEmpty,
          backChecks: 6,
        );
      });
    }
  }
}
