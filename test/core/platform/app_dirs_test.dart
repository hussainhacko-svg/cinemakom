// Where the app keeps its files on desktop (docs/PACKAGING.md §2): the XDG
// Base Directory and user-dirs rules on Linux, Local AppData on Windows.

import 'package:cinemakom/core/platform/app_dirs.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = '/home/me';

AppDirs _linux([Map<String, String> env = const {}, String? userDirs]) =>
    linuxAppDirs(env: env, home: _home, userDirs: userDirs);

void main() {
  group('Linux', () {
    test('the XDG defaults, under the app ID', () {
      final d = _linux();
      expect(d.data, '/home/me/.local/share/io.github.sharon_xa.cinemakom');
      expect(d.cache, '/home/me/.cache/io.github.sharon_xa.cinemakom');
      expect(d.state, '/home/me/.local/state/io.github.sharon_xa.cinemakom');
      expect(d.videos, '/home/me/Videos');
    });

    test('the XDG variables when set (a Flatpak sets them)', () {
      final d = _linux({
        'XDG_DATA_HOME': '/home/me/.var/app/x/data',
        'XDG_CACHE_HOME': '/home/me/.var/app/x/cache',
        'XDG_STATE_HOME': '/home/me/.var/app/x/.local/state',
      });
      expect(d.data, '/home/me/.var/app/x/data/io.github.sharon_xa.cinemakom');
      expect(
        d.cache,
        '/home/me/.var/app/x/cache/io.github.sharon_xa.cinemakom',
      );
      expect(
        d.state,
        '/home/me/.var/app/x/.local/state/io.github.sharon_xa.cinemakom',
      );
    });

    test('an empty or relative variable is ignored, as the spec says', () {
      final d = _linux({'XDG_DATA_HOME': '', 'XDG_CACHE_HOME': 'cache'});
      expect(d.data, '/home/me/.local/share/io.github.sharon_xa.cinemakom');
      expect(d.cache, '/home/me/.cache/io.github.sharon_xa.cinemakom');
    });

    group('the videos folder', () {
      test('from user-dirs.dirs, translated', () {
        const file = '''
# This file is written by xdg-user-dirs-update
XDG_DESKTOP_DIR="\$HOME/Bureau"
XDG_VIDEOS_DIR="\$HOME/Vidéos"
''';
        expect(_linux(const {}, file).videos, '/home/me/Vidéos');
      });

      test('Arabic names and absolute paths', () {
        expect(
          _linux(const {}, 'XDG_VIDEOS_DIR="\$HOME/الفيديو"').videos,
          '/home/me/الفيديو',
        );
        expect(
          _linux(const {}, 'XDG_VIDEOS_DIR="/mnt/media/Films"').videos,
          '/mnt/media/Films',
        );
      });

      test(r'just $HOME means turned off: the default', () {
        expect(
          _linux(const {}, 'XDG_VIDEOS_DIR="\$HOME/"').videos,
          '/home/me/Videos',
        );
        expect(
          _linux(const {}, 'XDG_VIDEOS_DIR="\$HOME"').videos,
          '/home/me/Videos',
        );
      });

      test('comments and other keys are skipped; a relative path is no '
          'folder', () {
        const file = '''
#XDG_VIDEOS_DIR="\$HOME/Old"
XDG_VIDEOS_DIR_BACKUP="\$HOME/Nope"
XDG_VIDEOS_DIR="Films"
''';
        expect(_linux(const {}, file).videos, '/home/me/Videos');
      });

      test('the variable when the file has no line for it', () {
        expect(
          _linux(const {
            'XDG_VIDEOS_DIR': '/srv/videos',
          }, 'XDG_MUSIC_DIR=x').videos,
          '/srv/videos',
        );
      });

      test('the file wins over the variable, as xdg-user-dir does', () {
        expect(
          _linux(const {
            'XDG_VIDEOS_DIR': '/srv/videos',
          }, 'XDG_VIDEOS_DIR="\$HOME/Films"').videos,
          '/home/me/Films',
        );
      });
    });

    test('xdgUserDir for another folder uses its own fallback', () {
      expect(
        xdgUserDir(
          'DOWNLOAD',
          fallback: 'Downloads',
          env: const {},
          home: _home,
        ),
        '/home/me/Downloads',
      );
    });
  });

  test('Windows: everything in Local AppData, downloads in Videos', () {
    final d = windowsAppDirs(
      local: r'C:\Users\me\AppData\Local\io.github.sharon_xa\Cinemakom',
      videos: r'D:\Videos',
    );
    expect(d.data, r'C:\Users\me\AppData\Local\io.github.sharon_xa\Cinemakom');
    expect(
      d.cache,
      r'C:\Users\me\AppData\Local\io.github.sharon_xa\Cinemakom\cache',
    );
    expect(d.state, d.data);
    expect(d.videos, r'D:\Videos');
  });

  test('Android and tests have none: the packages keep their defaults', () {
    expect(AppDirs.current, isNull);
  });
}
