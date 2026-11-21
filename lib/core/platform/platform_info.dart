import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _platformChannel = MethodChannel(
  'io.github.sharon_xa.cinemakom/platform',
);

bool _isTv = false;
bool _isAppleTv = false;

/// Test override for [isTv], mirroring [debugDefaultTargetPlatformOverride].
@visibleForTesting
bool? debugIsTvOverride;

/// Test override for [isAppleTv], mirroring [debugIsTvOverride].
@visibleForTesting
bool? debugIsAppleTvOverride;

/// Marks the process as running on Apple TV (tvOS), called once by
/// `lib/main_tvos.dart`. Kept out of `lib/main.dart` so all other platforms
/// stay unchanged.
void markAppleTv() {
  _isAppleTv = true;
}

/// Queries native platform flags once at startup (currently Android TV
/// Leanback / television UI mode, docs/TV.md).
Future<void> initPlatformInfo() async {
  if (!isAndroid) {
    _isTv = false;
    return;
  }
  try {
    _isTv = (await _platformChannel.invokeMethod<bool>('isTv')) ?? false;
  } on Object {
    _isTv = false;
  }
}

/// Keeps the Apple TV display awake during playback via UIKit's
/// `isIdleTimerDisabled` on the platform channel. No-op elsewhere.
Future<void> setAppleTvWakelock({required bool on}) async {
  if (!isAppleTv) return;
  try {
    await _platformChannel.invokeMethod<void>('setWakelock', on);
  } on Object {
    // Platform channel unavailable (tests, simulator without plugin).
  }
}

/// Platform checks used across the app. Use these instead of `dart:io`
/// `Platform` so the logic stays testable via [debugDefaultTargetPlatformOverride]
/// and [debugIsTvOverride].
bool get isDesktop =>
    switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS => true,
      _ => false,
    } &&
    !kIsWeb;

bool get isMobile =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    } &&
    !kIsWeb;

bool get isAndroid =>
    defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

/// True when running on Apple TV (tvOS).
bool get isAppleTv => (debugIsAppleTvOverride ?? _isAppleTv) && !kIsWeb;

/// True when running on Android TV / Google TV or Apple TV.
bool get isTv => (debugIsTvOverride ?? (_isTv || isAppleTv)) && !kIsWeb;

/// Whether offline downloads are supported on this platform. Disabled on
/// Apple TV because tvOS does not guarantee permanent bulk local storage.
bool get supportsDownloads => !isAppleTv;

/// `--dart-define=CINEMAKOM_TV=true` shows the TV UI on any platform, so it
/// can be built and tested on Linux (docs/TV.md §4.1).
const forceTvUi = bool.fromEnvironment('CINEMAKOM_TV');

/// Whether `main` starts the TV UI (`lib/tv`) instead of the phone and
/// desktop one. Only `main` reads it: the phone UI never checks for TV.
bool get useTvUi => isTv || forceTvUi;

/// True on touch phones and tablets (Android/iOS excluding Android TV).
bool get isTouchMobile => isMobile && !isTv;
