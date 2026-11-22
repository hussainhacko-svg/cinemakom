import 'dart:io';

import 'package:cinemakom/core/downloads/kept_resume_store.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/repositories/download_url_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/app_harness.dart' show fixtureApi;
import '../../repositories/fake_api_client.dart';

void main() {
  late Directory dir;
  late String storePath;
  KeptResumeStore store() => KeptResumeStore(() async => storePath);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kept');
    storePath = p.join(dir.path, 'kept.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File partial(String name, int bytes) =>
      File(p.join(dir.path, name))..writeAsBytesSync(List.filled(bytes, 1));

  group('KeptResumeStore (resume data past a final failure)', () {
    test('keeps what a whole partial file can continue from, across a '
        'restart of the app', () async {
      final file = partial('t1', 100);
      final a = store();
      await a.keep(
        'm1',
        {'data': file.path},
        tempPath: file.path,
        startByte: 100,
      );
      await a.flush();

      final b = store();
      expect(await b.usable('m1'), {'data': file.path});
      expect(await b.tempPaths({'m1'}), {'m1': file.path});
    });

    test(
      'refuses or forgets a partial file that is gone or too short',
      () async {
        final short = partial('t2', 10);
        final s = store();
        await s.keep('m2', {}, tempPath: short.path, startByte: 50);
        expect(await s.usable('m2'), isNull);

        final file = partial('t3', 100);
        await s.keep('m3', {}, tempPath: file.path, startByte: 100);
        file.deleteSync();
        expect(await s.usable('m3'), isNull);
        expect(await s.tempPaths({'m3'}), isEmpty);
      },
    );

    test('forgets tasks whose download is gone', () async {
      final file = partial('t4', 5);
      final s = store();
      await s.keep('old', {}, tempPath: file.path, startByte: 5);
      expect(await s.tempPaths({'other'}), isEmpty);
      expect(await s.usable('old'), isNull);
    });

    test('a corrupt store file is an empty store', () async {
      File(storePath).writeAsStringSync('{not json');
      expect(await store().usable('x'), isNull);
    });
  });

  group('download URL refresh', () {
    test('reads the signed expiry', () {
      expect(
        signedUrlExpiry(
          'https://cdn/v.mp4?AWSAccessKeyId=a&Expires=1795000000',
        ),
        DateTime.fromMillisecondsSinceEpoch(1795000000 * 1000, isUtc: true),
      );
      expect(signedUrlExpiry('https://cdn/v.mp4'), isNull);
    });

    test(
      'fetches a fresh URL in the same quality, none when it is gone',
      () async {
        final api = fixtureApi();
        final url = await freshDownloadUrl('3119279', '720p', api: api);
        expect(url, isNotNull);
        expect(
          api.requests.single.path,
          startsWith(ApiEndpoints.streams('3119279').path),
        );
        expect(await freshDownloadUrl('3119279', '2160p', api: api), isNull);
      },
    );

    test('throws when the API is unreachable (the old URL stays)', () async {
      final api = FakeApiClient([
        FakeApiClient.path('transcoddedFiles', offline),
      ]);
      expect(freshDownloadUrl('1', '720p', api: api), throwsA(anything));
    });
  });
}
