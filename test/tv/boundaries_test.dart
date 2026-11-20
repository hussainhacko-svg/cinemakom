import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The TV UI and the phone/desktop UI stay apart (docs/TV.md §4.3): this
/// reads every import line in `lib`, so a crossing fails here instead of
/// drifting in.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => p.posix.normalize(f.path.replaceAll(r'\', '/')))
      .toList();

  test('lib/features and lib/app never import lib/tv', () {
    final crossings = [
      for (final file in files)
        if (_isPhoneUi(file))
          for (final target in _imports(file))
            if (target.startsWith('lib/tv/')) '$file → $target',
    ];
    expect(crossings, isEmpty);
  });

  test('lib/tv imports only the shared parts of lib/app and lib/features', () {
    final crossings = [
      for (final file in files)
        if (file.startsWith('lib/tv/'))
          for (final target in _imports(file))
            if (_isPhoneUi(target) && !_shared(target)) '$file → $target',
    ];
    expect(
      crossings,
      isEmpty,
      reason:
          'Move what the TV needs out of the phone screen into a '
          '*_providers.dart / *_flow.dart file (docs/TV.md §3), or add a '
          'layout-free piece to _sharedFiles.',
    );
  });

  test('lib/features and lib/app never check isTv', () {
    final checks = [
      for (final file in files)
        if (_isPhoneUi(file))
          for (final (i, line) in File(file).readAsLinesSync().indexed)
            if (!line.trimLeft().startsWith('//') &&
                RegExp(r'\b(isTv|useTvUi|forceTvUi)\b').hasMatch(line))
              '$file:${i + 1}',
    ];
    expect(checks, isEmpty, reason: 'Platform behaviour uses isTouchMobile.');
  });
}

bool _isPhoneUi(String path) =>
    path.startsWith('lib/app/') || path.startsWith('lib/features/');

/// Layout-free pieces of lib/app and lib/features that the TV UI reuses
/// (docs/TV.md §3). Providers, flows and logic files are shared by name.
const _sharedDirs = ['lib/app/l10n/', 'lib/app/theme/', 'lib/app/brand/'];
const _sharedFiles = {
  'lib/app/catalog_providers.dart',
  'lib/app/navigation_args.dart', // the routes' arguments (TV.md §4.4)
  'lib/app/widgets/media_image.dart',
  'lib/app/widgets/bulb_loader.dart',
  'lib/app/widgets/error_view.dart', // errorMessage
  'lib/app/widgets/media_text.dart', // context.joinMeta / context.isolate
  'lib/features/home/widgets/hero_title.dart', // the fitting, at TV size
  'lib/features/search/search_history.dart',
  'lib/features/details/episode_view.dart', // seasons, blocks of 50, anchor
  'lib/features/details/play_target.dart', // Play or Resume
  'lib/features/player/player_controller.dart',
  'lib/features/player/player_state.dart',
  'lib/features/player/quality.dart',
  'lib/features/player/subtitles.dart',
  'lib/features/player/up_next.dart',
};

bool _shared(String path) =>
    _sharedFiles.contains(path) ||
    _sharedDirs.any(path.startsWith) ||
    path.endsWith('_providers.dart') ||
    path.endsWith('_flow.dart');

final _importLine = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// The files in `lib` that [file] imports or exports, as `lib/...` paths.
Iterable<String> _imports(String file) sync* {
  for (final line in File(file).readAsLinesSync()) {
    final uri = _importLine.firstMatch(line)?.group(1);
    if (uri == null || uri.startsWith('dart:')) continue;
    if (uri.startsWith('package:')) {
      if (uri.startsWith('package:cinemakom/')) {
        yield 'lib/${uri.substring('package:cinemakom/'.length)}';
      }
      continue;
    }
    yield p.posix.normalize(p.posix.join(p.posix.dirname(file), uri));
  }
}
