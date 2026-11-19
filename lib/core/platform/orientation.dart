import 'package:flutter/services.dart';

import '../storage/preferences.dart';
import 'platform_info.dart';

/// The browsing screens' orientation on phones and tablets: upright, or
/// whatever the device's auto-rotate allows when the user picked
/// [ScreenRotation.auto] in Settings. Desktop windows are left alone.
void setBrowseOrientation(ScreenRotation rotation) {
  if (!isMobile) return;
  SystemChrome.setPreferredOrientations(switch (rotation) {
    ScreenRotation.portrait => const [DeviceOrientation.portraitUp],
    // No preference: the system decides, following its auto-rotate lock.
    ScreenRotation.auto => const [],
  });
}

/// The player is landscape, on either side. With both sides allowed, the
/// system only flips between them when its auto-rotate is on (Android maps
/// this to `SCREEN_ORIENTATION_USER_LANDSCAPE`).
void setPlayerOrientation() {
  if (!isMobile) return;
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
