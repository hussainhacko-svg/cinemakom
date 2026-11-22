import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The fallback font libass uses for styled (ASS) subtitles, whose files
/// name fonts no device has. It must be the Regular file: with only the
/// Medium one, libass renders nothing (PLAYER.md §13).
const libassFontAsset = 'assets/fonts/IBMPlexSansArabic-Regular.ttf';
const libassFontFamily = 'IBM Plex Sans Arabic';

Future<String?>? _fontsDir;

/// A folder holding [libassFontAsset], for mpv's `sub-fonts-dir` on desktop
/// (libass reads fonts from disk, not from Flutter assets). Android
/// gets the font through `PlayerConfiguration.libassAndroidFont` instead.
/// Copied once per run; `null` if the copy fails (libass then falls back to
/// the system's fonts).
Future<String?> libassFontsDir() => _fontsDir ??= _copyFont();

Future<String?> _copyFont() async {
  try {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/libass-fonts',
    );
    final file = File('${dir.path}/${libassFontAsset.split('/').last}');
    if (!file.existsSync()) {
      final data = await rootBundle.load(libassFontAsset);
      await dir.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return dir.path;
  } on Object {
    return null;
  }
}
