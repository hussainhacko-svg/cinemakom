import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_info.dart';

/// Reports whether the device currently has a usable network connection
/// (docs/DOWNLOADS.md §5.5). Wrapped behind an overridable provider so widget
/// and unit tests never hang on an unmocked platform channel.
abstract interface class ConnectivityMonitor {
  /// Emits `true` when online and `false` when offline.
  Stream<bool> get onChanged;
}

class PlatformConnectivityMonitor implements ConnectivityMonitor {
  static const _channel = EventChannel(
    'io.github.sharon_xa.cinemakom/connectivity',
  );

  @override
  Stream<bool> get onChanged {
    if (!isAndroid) return const Stream.empty();
    return _channel
        .receiveBroadcastStream()
        .where((event) => event is bool)
        .cast<bool>()
        .distinct()
        .handleError((Object _) {});
  }
}

/// Always-online stub used in tests unless overridden.
class AlwaysOnlineConnectivity implements ConnectivityMonitor {
  const AlwaysOnlineConnectivity();

  @override
  Stream<bool> get onChanged => const Stream.empty();
}

final connectivityMonitorProvider = Provider<ConnectivityMonitor>(
  (ref) => PlatformConnectivityMonitor(),
);
