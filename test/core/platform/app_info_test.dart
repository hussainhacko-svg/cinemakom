// The device line of bug reports and the log header. Inside a Flatpak it
// must name the user's system, not the runtime.

import 'package:cinemakom/core/platform/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('os-release: PRETTY_NAME, unquoted', () {
    expect(
      osReleaseName('NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04.3 LTS"\n'),
      'Ubuntu 24.04.3 LTS',
    );
    expect(osReleaseName("PRETTY_NAME='Fedora Linux 43'"), 'Fedora Linux 43');
    expect(osReleaseName('PRETTY_NAME=Arch'), 'Arch');
  });

  test('os-release: NAME without PRETTY_NAME; nothing is null', () {
    expect(osReleaseName('ID=x\nNAME="Void"\n'), 'Void');
    expect(osReleaseName('ID=x\nPRETTY_NAME=""\n'), isNull);
    expect(osReleaseName(''), isNull);
  });

  test('outside a Flatpak there is no host name', () {
    expect(flatpakHostName(), isNull);
  });
}
