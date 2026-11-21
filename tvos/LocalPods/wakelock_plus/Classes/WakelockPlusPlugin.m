#import "WakelockPlusPlugin.h"

@implementation WakelockPlusPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // Apple TV wakelock is handled directly via UIApplication.isIdleTimerDisabled
  // on the io.github.sharon_xa.cinemakom/platform channel in AppDelegate.swift.
}

@end
