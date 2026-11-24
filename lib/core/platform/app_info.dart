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
      device = (await info.linuxInfo).prettyName;
    } else if (Platform.isWindows) {
      final w = await info.windowsInfo;
      device = '${w.productName} ${w.displayVersion}';
    }
  } on Object {
    // The platform's name is enough.
  }
  return (version: version, device: device);
}
