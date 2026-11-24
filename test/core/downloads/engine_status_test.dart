import 'package:background_downloader/background_downloader.dart';
import 'package:cinemakom/core/downloads/background_file_downloader.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/data/repositories/download_url_refresh.dart'
    show downloadUrlRefreshMargin;
import 'package:flutter_test/flutter_test.dart';

void main() {
  DownloaderStatus failedWith(TaskException e) =>
      BackgroundFileDownloader.statusFrom('t', TaskStatus.failed, e);

  test('a refused connection reported as a file error is a connection error '
      '(seen on desktop, 2026-11-22)', () {
    final s = failedWith(
      TaskFileSystemException(
        'ClientException with SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 111)',
      ),
    );
    expect((s.connectionError, s.fileError), (true, false));
  });

  test('real file errors and a full disk stay what they are', () {
    final file = failedWith(TaskFileSystemException('Permission denied'));
    expect((file.fileError, file.connectionError), (true, false));
    final space = failedWith(
      TaskFileSystemException('Insufficient space to store the file'),
    );
    expect((space.noSpace, space.fileError), (true, false));
  });

  test('a timeout is a timeout, not a dropped connection', () {
    final s = failedWith(TaskConnectionException('Task timed out'));
    expect((s.timedOut, s.connectionError), (true, false));
  });

  test('HTTP errors keep their code', () {
    final s = failedWith(TaskHttpException('Forbidden', 403));
    expect(s.httpCode, 403);
  });

  // What each engine really sends. Android's description is the Java
  // exception's toString(), and every IOException but a socket one is a
  // file-system error there (TaskRunner.setTaskException).
  group('the reason, from real descriptions', () {
    String reason(DownloaderStatus s) => [
      if (s.noSpace) 'noSpace',
      if (s.fileError) 'file',
      if (s.connectionError) 'connection',
      if (s.timedOut) 'timedOut',
      if (s.resumeError) 'resume',
    ].join(',');

    final cases = <String, (TaskException, String)>{
      'Android: unknown host': (
        TaskFileSystemException(
          'java.net.UnknownHostException: Unable to resolve host '
          '"cdn.example": No address associated with hostname',
        ),
        'connection',
      ),
      'Android: TLS protocol error': (
        TaskFileSystemException(
          'javax.net.ssl.SSLProtocolException: Read error: ssl=0x7b4c: '
          'Failure in SSL library, usually a protocol error',
        ),
        'connection',
      ),
      'Android: stream cut short': (
        TaskFileSystemException(
          'java.net.ProtocolException: unexpected end of stream',
        ),
        'connection',
      ),
      'Android: HTTP/2 stream reset': (
        TaskFileSystemException(
          'com.android.okhttp.internal.http2.StreamResetException: '
          'stream was reset: PROTOCOL_ERROR',
        ),
        'connection',
      ),
      'Android: EOF': (
        TaskFileSystemException('java.io.EOFException'),
        'connection',
      ),
      'Android: socket timeout': (
        TaskConnectionException('java.net.SocketTimeoutException: timeout'),
        'connection',
      ),
      'Android: refused': (
        TaskConnectionException(
          'java.net.ConnectException: Failed to connect to /10.0.0.1:443',
        ),
        'connection',
      ),
      'Android: the engine finds too little space': (
        TaskFileSystemException(
          'Insufficient space to store the file to be downloaded',
        ),
        'noSpace',
      ),
      'Android: the disk fills up while writing': (
        TaskFileSystemException(
          'java.io.IOException: write failed: ENOSPC (No space left on '
          'device)',
        ),
        'noSpace',
      ),
      'Android: no permission': (
        TaskFileSystemException(
          'java.io.FileNotFoundException: /storage/emulated/0/Movies/'
          'Cinemakom/x.mp4: open failed: EACCES (Permission denied)',
        ),
        'file',
      ),
      'desktop: a folder called "My Space" is no full disk': (
        TaskFileSystemException(
          "FileSystemException: Cannot open file, path = '/home/me/My "
          "Space/x.mp4' (OS Error: Permission denied, errno = 13)",
        ),
        'file',
      ),
      'Linux: disk full': (
        TaskFileSystemException(
          "FileSystemException: writeFrom failed, path = '/home/me/x.part' "
          '(OS Error: No space left on device, errno = 28)',
        ),
        'noSpace',
      ),
      'Windows: disk full': (
        TaskFileSystemException(
          r"FileSystemException: writeFrom failed, path = 'C:\Users\me\x.part'"
          ' (OS Error: There is not enough space on the disk., errno = 112)',
        ),
        'noSpace',
      ),
      'desktop: connection reset': (
        TaskConnectionException(
          'ClientException: Connection reset by peer, uri=https://cdn/x.mp4',
        ),
        'connection',
      ),
      'the engine: timed out': (
        TaskConnectionException('Task timed out'),
        'timedOut',
      ),
      'the engine: resume refused': (
        TaskResumeException('Resume failed: ETag changed'),
        'resume',
      ),
      'stopped by the system: none of these': (
        TaskException('Task was stopped by the system'),
        '',
      ),
    };
    for (final MapEntry(key: name, value: (e, expected)) in cases.entries) {
      test(name, () => expect(reason(failedWith(e)), expected));
    }

    test('the raw description is kept for Details', () {
      final e = TaskFileSystemException('java.io.EOFException');
      expect(failedWith(e).detail, e.toString());
    });
  });

  group('statusFrom', () {
    test('every engine status has a state', () {
      const expected = {
        TaskStatus.enqueued: DownloaderState.queued,
        TaskStatus.waitingToRetry: DownloaderState.queued,
        TaskStatus.running: DownloaderState.running,
        TaskStatus.paused: DownloaderState.paused,
        TaskStatus.complete: DownloaderState.complete,
        TaskStatus.canceled: DownloaderState.canceled,
        TaskStatus.failed: DownloaderState.failed,
        TaskStatus.notFound: DownloaderState.failed,
      };
      expect(expected.keys, unorderedEquals(TaskStatus.values));
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(
          BackgroundFileDownloader.statusFrom('t', key, null).state,
          value,
          reason: key.name,
        );
      }
    });

    test('a success has no reason and no detail', () {
      final s = BackgroundFileDownloader.statusFrom(
        't',
        TaskStatus.complete,
        null,
        responseStatusCode: 200,
      );
      expect(
        (s.noSpace, s.fileError, s.connectionError, s.timedOut, s.detail),
        (false, false, false, false, null),
      );
    });

    test('the HTTP code comes from the update without an HTTP exception', () {
      expect(
        BackgroundFileDownloader.statusFrom(
          't',
          TaskStatus.failed,
          TaskException('Not found'),
          responseStatusCode: 404,
        ).httpCode,
        404,
      );
      // The engine's "none" values.
      for (final none in [0, -1]) {
        expect(
          BackgroundFileDownloader.statusFrom(
            't',
            TaskStatus.failed,
            null,
            responseStatusCode: none,
          ).httpCode,
          isNull,
        );
      }
    });
  });

  group('progressFrom', () {
    final task = DownloadTask(taskId: 't', url: 'https://cdn/x.mp4');

    test('fraction, size, speed in bytes per second, time left', () {
      final p = BackgroundFileDownloader.progressFrom(
        TaskProgressUpdate(task, 0.25, 4000, 2, const Duration(seconds: 30)),
      )!;
      expect(p.taskId, 't');
      expect(p.fraction, 0.25);
      expect(p.expectedBytes, 4000);
      expect(p.bytesPerSecond, 2 * 1024 * 1024);
      expect(p.timeLeft, const Duration(seconds: 30));
    });

    test("what the engine doesn't know is null", () {
      final p = BackgroundFileDownloader.progressFrom(
        TaskProgressUpdate(task, 0.5),
      )!;
      expect(
        (p.expectedBytes, p.bytesPerSecond, p.timeLeft),
        (null, null, null),
      );
    });

    test('status signals are no progress; over 1 is 1', () {
      for (final signal in [-1.0, -2.0, -4.0, -5.0]) {
        expect(
          BackgroundFileDownloader.progressFrom(
            TaskProgressUpdate(task, signal),
          ),
          isNull,
        );
      }
      expect(
        BackgroundFileDownloader.progressFrom(TaskProgressUpdate(task, 1.2))!
            .fraction,
        1,
      );
    });
  });

  group('knownFrom', () {
    DownloadTask task(String id) =>
        DownloadTask(taskId: id, url: 'https://cdn/$id.mp4');
    TaskRecord record(
      String id,
      TaskStatus status, {
      double progress = 0.4,
      int size = 1000,
      TaskException? exception,
    }) => TaskRecord(task(id), status, progress, size, exception);

    test('a record: its state, progress and size', () {
      final k = BackgroundFileDownloader.knownFrom([
        record('a', TaskStatus.running),
      ], const []);
      expect(k['a']!.state, DownloaderState.running);
      expect(k['a']!.fraction, 0.4);
      expect(k['a']!.expectedBytes, 1000);
      expect(k['a']!.failure, isNull);
    });

    test('a failed record says why', () {
      final k = BackgroundFileDownloader.knownFrom([
        record(
          'a',
          TaskStatus.failed,
          exception: TaskFileSystemException(
            'java.net.UnknownHostException: Unable to resolve host "cdn"',
          ),
        ),
      ], const []);
      expect(k['a']!.state, DownloaderState.failed);
      expect(k['a']!.failure!.connectionError, isTrue);
    });

    test('unknown progress and size are null; over 1 is 1', () {
      final k = BackgroundFileDownloader.knownFrom([
        record('a', TaskStatus.enqueued, progress: -1, size: -1),
        record('b', TaskStatus.running, progress: 1.5),
      ], const []);
      expect((k['a']!.fraction, k['a']!.expectedBytes), (null, null));
      expect(k['b']!.fraction, 1);
    });

    test('a paused or finished record keeps its state while the engine '
        'still lists the task (PR #4 review, critical 3)', () {
      final k = BackgroundFileDownloader.knownFrom(
        [record('p', TaskStatus.paused), record('c', TaskStatus.complete)],
        [task('p'), task('c')],
      );
      expect(k['p']!.state, DownloaderState.paused);
      expect(k['c']!.state, DownloaderState.complete);
    });

    test('a failed or cancelled record the engine queued again is queued, '
        'keeping its progress', () {
      final k = BackgroundFileDownloader.knownFrom(
        [record('f', TaskStatus.failed), record('x', TaskStatus.canceled)],
        [task('f'), task('x')],
      );
      expect(k['f']!.state, DownloaderState.queued);
      expect(k['f']!.fraction, 0.4);
      expect(k['f']!.failure, isNull);
      expect(k['x']!.state, DownloaderState.queued);
    });

    test('a queued task without a record is queued', () {
      final k = BackgroundFileDownloader.knownFrom(const [], [task('q')]);
      expect(k['q']!.state, DownloaderState.queued);
      expect(k['q']!.fraction, isNull);
    });
  });

  group('refreshOptions', () {
    const signed = 'https://cdn/v.mp4?AWSAccessKeyId=a&Expires=1795000000';
    final expires = DateTime.fromMillisecondsSinceEpoch(
      1795000000 * 1000,
      isUtc: true,
    );

    test('a signed link is refreshed a margin before it expires', () {
      final auth = BackgroundFileDownloader.refreshOptions(
        signed,
        '720p',
      )!.auth!;
      expect(
        auth.accessTokenExpiryTime,
        expires.subtract(downloadUrlRefreshMargin),
      );
    });

    test('nothing to refresh without an expiry or a quality to ask for', () {
      expect(
        BackgroundFileDownloader.refreshOptions('https://cdn/v.mp4', '720p'),
        isNull,
      );
      expect(BackgroundFileDownloader.refreshOptions(signed, null), isNull);
      expect(BackgroundFileDownloader.refreshOptions(signed, ''), isNull);
    });
  });
}
