import 'package:flutter/services.dart';

import 'platform_info.dart';

const _channel = MethodChannel('io.github.sharon_xa.cinemakom/platform');

/// The free bytes on the disk holding [path], or `null` where it can't be
/// read. Android only (the TV's download panel, docs/TV.md §7.4); other
/// platforms answer `null`.
Future<int?> freeBytes(String path) async {
  if (!isAndroid) return null;
  try {
    return await _channel.invokeMethod<int>('freeBytes', {'path': path});
  } on Object {
    return null;
  }
}
