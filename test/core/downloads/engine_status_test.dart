import 'package:background_downloader/background_downloader.dart';
import 'package:cinemakom/core/downloads/background_file_downloader.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
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
}
