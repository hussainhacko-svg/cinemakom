// The AppImage's own libmpv must win over the system's (docs/PACKAGING.md
// §3): two libmpv in one process abort when a video opens.

import 'package:cinemakom/core/player/media_kit_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the libmpv next to the app is used', () {
    expect(
      bundledLibmpv(
        executable: '/home/u/.local/lib/cinemakom/usr/lib/cinemakom/cinemakom',
        exists: (path) => true,
      ),
      '/home/u/.local/lib/cinemakom/usr/lib/cinemakom/lib/libmpv.so.2',
    );
  });

  test('without one (a development build), the system libmpv is used', () {
    expect(
      bundledLibmpv(
        executable: '/src/build/linux/x64/debug/bundle/cinemakom',
        exists: (path) => false,
      ),
      isNull,
    );
  });
}
