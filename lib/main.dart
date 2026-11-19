import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/app.dart';
import 'core/platform/orientation.dart';
import 'core/platform/platform_info.dart';
import 'core/storage/preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  registerFontLicenses();
  // Upright from the first frame; the saved choice applies once settings
  // load (CinemakomApp).
  setBrowseOrientation(ScreenRotation.portrait);

  // cached_network_image stores its cache index in sqflite, which has no
  // native plugin on Linux/Windows. Route it through the FFI implementation.
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // No automatic provider retries: ApiClient already retries a failed GET
  // once, and the screens show errors with a "Try again" button instead of
  // a loader that silently spins.
  runApp(const ProviderScope(retry: noRetry, child: CinemakomApp()));
}

/// The bundled fonts' licenses (SIL OFL 1.1), for the app's licenses page.
const fontLicenses = {
  'Big Shoulders Display': 'BigShouldersDisplay-OFL.txt',
  'Reem Kufi': 'ReemKufi-OFL.txt',
  'IBM Plex Sans': 'IBMPlexSans-OFL.txt',
  'IBM Plex Sans Arabic': 'IBMPlexSansArabic-OFL.txt',
};

/// For [ProviderScope.retry]: never retry a failed provider.
Duration? noRetry(int retryCount, Object error) => null;

void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: file) in fontLicenses.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/licenses/$file'));
    }
  });
}
