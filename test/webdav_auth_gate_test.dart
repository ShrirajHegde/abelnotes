// After the server answers 401 or 429, the client stops sending requests
// itself: a changed password must not be retried into Nextcloud's brute-force
// throttle, and a 429 must be waited out.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/webdav_service.dart';

void main() {
  late HttpServer server;
  late int status;
  late int hits;
  late Map<String, String> headers;

  setUp(() async {
    status = 207;
    hits = 0;
    headers = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits++;
      await req.drain<void>();
      req.response.statusCode = status;
      headers.forEach(req.response.headers.set);
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  WebDavService service({void Function(bool)? onRejected}) => WebDavService(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
        onAuthRejectedChanged: onRejected,
      );

  test('a 401 is reported once and later requests never leave the client',
      () async {
    final events = <bool>[];
    final dav = service(onRejected: events.add);
    addTearDown(dav.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 200)); // pre-warm

    status = 401;
    await expectLater(dav.getVersion('/a'), throwsA(isA<WebDavException>()));
    expect(events, [true]);
    expect(dav.authRejected, isTrue);

    final before = hits;
    for (var i = 0; i < 5; i++) {
      await expectLater(
          dav.getVersion('/a'),
          throwsA(isA<WebDavException>()
              .having((e) => e.statusCode, 'statusCode', 401)));
    }
    expect(hits, before, reason: 'no request may reach the server');
    expect(await dav.getVersionFast('/a'), isNull);
    expect(hits, before);
  });

  test('a 429 backs requests off locally', () async {
    final dav = service();
    addTearDown(dav.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    status = 429;
    headers = {'retry-after': '120'};
    await expectLater(dav.getVersion('/a'), throwsA(isA<WebDavException>()));

    final before = hits;
    await expectLater(
        dav.listDirectory('/'),
        throwsA(isA<WebDavException>()
            .having((e) => e.statusCode, 'statusCode', 429)));
    expect(hits, before);
  });

  test('probeConnection tells a wrong password from a wrong address',
      () async {
    final dav = service();
    addTearDown(dav.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await dav.probeConnection(), ConnectionProbe.ok);

    status = 404;
    expect(await service().probeConnection(), ConnectionProbe.notAServer);

    status = 401;
    expect(await service().probeConnection(), ConnectionProbe.unauthorized);

    status = 500;
    expect(await service().probeConnection(), ConnectionProbe.serverError);

    final port = server.port;
    await server.close(force: true);
    final gone = WebDavService(
        serverUrl: 'http://127.0.0.1:$port', username: 'u', password: 'p');
    addTearDown(gone.dispose);
    expect(await gone.probeConnection(), ConnectionProbe.unreachable);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
}
