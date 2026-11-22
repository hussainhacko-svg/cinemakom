import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _platformChannel = MethodChannel(
  'io.github.sharon_xa.cinemakom/platform',
);

bool _isTv = false;

/// Test override for [isTv], mirroring [debugDefaultTargetPlatformOverride].
@visibleForTesting
bool? debugIsTvOverride;

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

/// Platform checks used across the app. Use these instead of `dart:io`
/// `Platform` so the logic stays testable via [debugDefaultTargetPlatformOverride]
/// and [debugIsTvOverride].
bool get isDesktop =>
    switch (defaultTargetPlatform) {
      TargetPlatform.linux || TargetPlatform.windows => true,
      _ => false,
    } &&
    !kIsWeb;

/// Phones, tablets and TVs: only Android (no Apple platforms, decision
/// 2026-11-22).
bool get isMobile => isAndroid;

bool get isAndroid =>
    defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

/// True when running on Android TV / Google TV.
bool get isTv => (debugIsTvOverride ?? _isTv) && !kIsWeb;

/// `--dart-define=CINEMAKOM_TV=true` shows the TV UI on any platform, so it
/// can be built and tested on Linux (docs/TV.md §4.1).
const forceTvUi = bool.fromEnvironment('CINEMAKOM_TV');

/// Whether `main` starts the TV UI (`lib/tv`) instead of the phone and
/// desktop one. Only `main` reads it: the phone UI never checks for TV.
bool get useTvUi => isTv || forceTvUi;

/// True on touch phones and tablets (Android, not Android TV).
bool get isTouchMobile => isMobile && !isTv;
