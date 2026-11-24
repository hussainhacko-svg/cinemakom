import 'dart:convert';
import 'dart:io';

import 'package:cinemakom/core/diagnostics/log_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// GET [url]: its status and body.
Future<(int, String, ContentType?)> get(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (response.statusCode, body, response.headers.contentType);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('log-server');
    file = File('${dir.path}/log.txt')
      ..writeAsStringSync('03:12:45 player  phase loading → ready\nماذا\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<LogServer> serve({Duration? lifetime}) async {
    final s = (await LogServer.start(
      file,
      address: InternetAddress.loopbackIPv4,
      lifetime: lifetime ?? const Duration(minutes: 10),
    ))!;
    addTearDown(s.close);
    return s;
  }

  test('the file, as UTF-8 text, at its address', () async {
    final s = await serve();
    expect(
      '${s.url}',
      matches(r'^http://127\.0\.0\.1:\d+/[0-9a-f]{32}/cinemakom-log\.txt$'),
    );
    final (status, body, type) = await get(s.url);
    expect(status, 200);
    expect(body, file.readAsStringSync());
    expect(type?.mimeType, 'text/plain');
    expect(type?.charset, 'utf-8');
  });

  test('nothing anywhere else: another path, a guess, a POST', () async {
    final s = await serve();
    for (final path in [
      '/',
      '/cinemakom-log.txt',
      '/${'0' * 32}/cinemakom-log.txt',
    ]) {
      final (status, body, _) = await get(s.url.replace(path: path));
      expect(status, 404, reason: path);
      expect(body, isEmpty);
    }
    final client = HttpClient();
    final post = await (await client.postUrl(s.url)).close();
    expect(post.statusCode, 404);
    client.close(force: true);
  });

  test('every time a new address', () async {
    final a = await serve();
    final b = await serve();
    expect(a.url.path, isNot(b.url.path));
  });

  test('closed: gone', () async {
    final s = await serve();
    await s.close();
    await expectLater(get(s.url), throwsA(isA<SocketException>()));
  });

  test('closes by itself after its lifetime', () async {
    final s = await serve(lifetime: const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await expectLater(get(s.url), throwsA(isA<SocketException>()));
  });

  test('a file removed meanwhile: an error answer, the server lives', () async {
    final s = await serve();
    file.deleteSync();
    final (status, _, _) = await get(s.url);
    expect(status, isNot(200));
    file.writeAsStringSync('back');
    expect((await get(s.url)).$2, 'back');
  });

  test('the local address is a private one, or none', () async {
    final a = await LogServer.localAddress();
    if (a == null) return;
    expect(a.type, InternetAddressType.IPv4);
    expect(a.address, matches(r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)'));
  });
}
