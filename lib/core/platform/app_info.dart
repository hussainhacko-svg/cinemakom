import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's version and the device, for bug reports and the log header.
typedef AppInfo = ({String version, String device});

/// `1.4.0 (12)` and `OnePlus CPH2423 · Android 15`. Never throws: what
/// can't be read says so.
Future<AppInfo> readAppInfo() async {
  var version = '?';
  try {
    final package = await PackageInfo.fromPlatform();
    version = '${package.version} (${package.buildNumber})';
  } on Object {
    // Unknown version.
  }
  var device = Platform.operatingSystem;
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      device =
          '${a.manufacturer} ${a.model} · Android ${a.version.release} '
          '(API ${a.version.sdkInt})';
    } else if (Platform.isLinux) {
      device = flatpakHostName() ?? (await info.linuxInfo).prettyName;
    } else if (Platform.isWindows) {
      final w = await info.windowsInfo;
      device = '${w.productName} ${w.displayVersion}';
    }
  } on Object {
    // The platform's name is enough.
  }
  return (version: version, device: device);
}

/// Inside a Flatpak, `/etc/os-release` is the runtime's ("GNOME 51"): the
/// user's system is in `/run/host/os-release`. "EndeavourOS (Flatpak)", or
/// `null` outside a Flatpak.
String? flatpakHostName() {
  try {
    if (!File('/.flatpak-info').existsSync()) return null;
    final host = File('/run/host/os-release');
    final name = host.existsSync()
        ? osReleaseName(host.readAsStringSync())
        : null;
    return '${name ?? 'Linux'} (Flatpak)';
  } on Object {
    return null;
  }
}

/// `PRETTY_NAME` (else `NAME`) of an os-release file, unquoted.
String? osReleaseName(String text) {
  String? value(String key) {
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (!l.startsWith('$key=')) continue;
      var v = l.substring(key.length + 1).trim();
      if (v.length >= 2 &&
          (v.startsWith('"') && v.endsWith('"') ||
              v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      return v.isEmpty ? null : v;
    }
    return null;
  }

  return value('PRETTY_NAME') ?? value('NAME');
}
