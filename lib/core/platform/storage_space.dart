import 'package:flutter/services.dart';

import 'platform_info.dart';

const _channel = MethodChannel('io.github.sharon_xa.cinemakom/platform');

/// The free bytes on the disk holding [path], or `null` where it can't be
/// read. Android only (the TV's download panel and phone space check); other
/// platforms answer `null`.
Future<int?> freeBytes(String path) async {
  if (!isAndroid) return null;
  try {
    return await _channel.invokeMethod<int>('freeBytes', {'path': path});
  } on Object {
    return null;
  }
}

/// Android API level (`Build.VERSION.SDK_INT`), or `null` off Android.
Future<int?> androidSdkInt() async {
  if (!isAndroid) return null;
  try {
    return await _channel.invokeMethod<int>('sdkInt');
  } on Object {
    return null;
  }
}

/// Public `Movies/Cinemakom` folder on Android, or `null` off Android.
Future<String?> androidPublicMoviesDir() async {
  if (!isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('publicMoviesDir');
  } on Object {
    return null;
  }
}

/// Whether the app can write to public `Movies/` on Android (always true on
/// API 29+, checks `WRITE_EXTERNAL_STORAGE` on API 24–28).
Future<bool> hasLegacyStoragePermission() async {
  if (!isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('hasLegacyStoragePermission') ??
        false;
  } on Object {
    return false;
  }
}

/// Asks Android's MediaScanner to index a newly finished video file so file
/// managers, video players and the gallery see it immediately.
Future<void> scanMediaFile(String path) async {
  if (!isAndroid) return;
  try {
    await _channel.invokeMethod<void>('scanFile', {'path': path});
  } on Object {
    // Best effort.
  }
}
