// One contract for both PreferenceStore implementations: the real one
// (shared_preferences, on its in-memory platform) and the in-memory one
// every widget test uses. The package throws on a value of the wrong type
// where the fake didn't, so the widget tests couldn't see that crash. If
// the two ever behave differently, they stop telling the truth.

import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

typedef MakeStore = Future<PreferenceStore> Function(Map<String, Object> seed);

final _stores = <String, MakeStore>{
  'SharedPreferencesStore': (seed) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(seed);
    return SharedPreferencesStore.create();
  },
  'MemoryPreferenceStore': (seed) async => MemoryPreferenceStore(seed),
};

/// The platform's side, for writes it refuses and settings it can't read
/// (a damaged file).
final class _BrokenPlatform extends InMemorySharedPreferencesAsync {
  _BrokenPlatform({this.reads = true}) : super.empty();

  /// Whether reading the saved settings works.
  final bool reads;

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    if (!reads) throw const FormatException('Unexpected end of input');
    return super.getPreferences(parameters, options);
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => throw PlatformException(code: 'disk-full');

  @override
  Future<bool> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) => throw PlatformException(code: 'disk-full');
}

List<String> _settingsLog() => [
  for (final e in EventLog.instance.recent)
    if (e.tag == 'settings') e.message,
];

void main() {
  for (final MapEntry(key: name, value: make) in _stores.entries) {
    group(name, () {
      test('missing values read as null', () async {
        final store = await make({});
        expect(store.getString(PreferenceKeys.language), isNull);
        expect(store.getInt(PreferenceKeys.defaultQuality), isNull);
      });

      test('reads back what it saved', () async {
        final store = await make({});
        await store.setString(PreferenceKeys.language, 'ar');
        await store.setInt(PreferenceKeys.defaultQuality, 720);
        expect(store.getString(PreferenceKeys.language), 'ar');
        expect(store.getInt(PreferenceKeys.defaultQuality), 720);
        await store.setString(PreferenceKeys.language, 'en');
        expect(store.getString(PreferenceKeys.language), 'en');
      });

      test('a value of another type reads as missing, never throws', () async {
        final store = await make({
          PreferenceKeys.language: 5,
          PreferenceKeys.defaultQuality: '1080',
          PreferenceKeys.playerVolume: 0.5,
          PreferenceKeys.searchHistory: ['a', 'b'],
        });
        expect(store.getString(PreferenceKeys.language), isNull);
        expect(store.getInt(PreferenceKeys.defaultQuality), isNull);
        expect(store.getInt(PreferenceKeys.playerVolume), isNull);
        expect(store.getString(PreferenceKeys.searchHistory), isNull);
        // The int under defaultQuality is still a string to getString.
        expect(store.getString(PreferenceKeys.defaultQuality), '1080');
        expect(readSettings(store), const AppSettings());
      });

      test('saving over a value of another type replaces it', () async {
        final store = await make({PreferenceKeys.defaultQuality: '1080'});
        await store.setInt(PreferenceKeys.defaultQuality, 2160);
        expect(store.getInt(PreferenceKeys.defaultQuality), 2160);
        expect(store.getString(PreferenceKeys.defaultQuality), isNull);
      });

      test(
        'a key outside PreferenceKeys.all is neither read nor kept',
        () async {
          final store = await make({'oldSetting': 'x'});
          expect(store.getString('oldSetting'), isNull);
          await store.setString('typo', 'y');
          await store.setInt('typo2', 1);
          expect(store.getString('typo'), isNull);
          expect(store.getInt('typo2'), isNull);
        },
      );

      test('every key the app uses can be saved', () async {
        final store = await make({});
        for (final key in PreferenceKeys.all) {
          await store.setString(key, 'v');
          expect(store.getString(key), 'v', reason: key);
        }
      });
    });
  }

  group('SharedPreferencesStore on a broken platform', () {
    test(
      'a refused write keeps the value for the session and is logged',
      () async {
        SharedPreferencesAsyncPlatform.instance = _BrokenPlatform();
        final store = await SharedPreferencesStore.create();
        await store.setString(PreferenceKeys.language, 'ar');
        await store.setInt(PreferenceKeys.defaultQuality, 720);
        expect(store.getString(PreferenceKeys.language), 'ar');
        expect(store.getInt(PreferenceKeys.defaultQuality), 720);
        expect(_settingsLog(), [
          startsWith("can't save language"),
          startsWith("can't save defaultQuality"),
        ]);
      },
    );

    test(
      'settings that can\'t be read start the app with the defaults',
      () async {
        SharedPreferencesAsyncPlatform.instance = _BrokenPlatform(reads: false);
        final store = await SharedPreferencesStore.open();
        expect(store, isA<MemoryPreferenceStore>());
        expect(readSettings(store), const AppSettings());
        expect(
          _settingsLog().single,
          startsWith("can't read the saved settings"),
        );
      },
    );

    test(
      'changing a setting never throws, and the app shows the change',
      () async {
        SharedPreferencesAsyncPlatform.instance = _BrokenPlatform();
        final container = ProviderContainer(retry: noRetry);
        addTearDown(container.dispose);
        await container.read(appStartupProvider.future);
        final notifier = container.read(settingsProvider.notifier);
        await notifier.setLanguage(AppLanguage.arabic);
        await notifier.setDefaultQuality(PreferredQuality.p480);
        await notifier.setSubtitleSize(SubtitleSize.large);
        final settings = container.read(settingsProvider);
        expect(settings.language, AppLanguage.arabic);
        expect(settings.defaultQuality, PreferredQuality.p480);
        expect(settings.subtitleSize, SubtitleSize.large);
      },
    );
  });

  test(
    'SharedPreferencesStore: what it saved is there after a restart',
    () async {
      final platform = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = platform;
      final first = await SharedPreferencesStore.create();
      await first.setString(PreferenceKeys.language, 'ar');
      await first.setInt(PreferenceKeys.defaultQuality, 2160);
      final second = await SharedPreferencesStore.create();
      expect(second.getString(PreferenceKeys.language), 'ar');
      expect(second.getInt(PreferenceKeys.defaultQuality), 2160);
    },
  );
}
