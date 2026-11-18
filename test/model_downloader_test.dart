import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/models/model_catalog.dart';
import 'package:andika/models/model_downloader.dart';
import 'package:andika/models/model_store.dart';

/// Serveur local qui sert [data] avec prise en charge de Range.
Future<HttpServer> serve(List<int> data, {bool honorRange = true}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && honorRange) {
      final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= data.length) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      } else {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
            HttpHeaders.contentRangeHeader, 'bytes $start-${data.length - 1}/${data.length}');
        req.response.add(data.sublist(start));
      }
    } else {
      req.response.headers.contentLength = data.length;
      req.response.add(data);
    }
    await req.response.close();
  });
  return server;
}


void main() {
  late Directory tmp;
  late ModelStore store;
  const model = WhisperModel(
    id: 't',
    label: 'T',
    fileName: 'ggml-t.bin',
    approxBytes: 1000,
    sha1: null,
    minRamBytes: 0,
    comfortRamBytes: 0,
    speedRating: 1,
    qualityRating: 1,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_models');
    store = ModelStore(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> okVerifier(WhisperModel m, String p) async {}

  HttpClient Function() clientFor(HttpServer server) {
    return () {
      final c = HttpClient();
      c.findProxy = (_) => 'DIRECT';
      c.connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
      return c;
    };
  }

  test('téléchargement complet puis installation', () async {
    final data = List<int>.generate(5000, (i) => i % 251);
    final server = await serve(data);
    final dl = ModelDownloader(store: store, clientFactory: clientFor(server), verifier: okVerifier);
    final events = await dl
        .download(model, freeStorageBytes: () async => 1 << 30)
        .toList();
    expect(events.last.receivedBytes, data.length);
    expect(store.isInstalled(model), isTrue);
    expect(store.file(model).readAsBytesSync(), data);
    expect(store.partFile(model).existsSync(), isFalse);
    await server.close(force: true);
  });

  test('reprise depuis un fichier partiel', () async {
    final data = List<int>.generate(5000, (i) => i % 251);
    final server = await serve(data);
    store.directory.createSync(recursive: true);
    store.partFile(model).writeAsBytesSync(data.sublist(0, 2000));
    final dl = ModelDownloader(store: store, clientFactory: clientFor(server), verifier: okVerifier);
    final events = await dl
        .download(model, freeStorageBytes: () async => 1 << 30)
        .toList();
    expect(events.first.receivedBytes, 2000);
    expect(store.file(model).readAsBytesSync(), data);
    await server.close(force: true);
  });

  test('serveur sans Range : on repart de zéro', () async {
    final data = List<int>.generate(3000, (i) => i % 200);
    final server = await serve(data, honorRange: false);
    store.directory.createSync(recursive: true);
    store.partFile(model).writeAsBytesSync(List<int>.filled(1000, 9));
    final dl = ModelDownloader(store: store, clientFactory: clientFor(server), verifier: okVerifier);
    await dl.download(model, freeStorageBytes: () async => 1 << 30).toList();
    expect(store.file(model).readAsBytesSync(), data);
    await server.close(force: true);
  });

  test('espace insuffisant', () async {
    final server = await serve(List<int>.filled(1000, 1));
    final dl = ModelDownloader(store: store, clientFactory: clientFor(server), verifier: okVerifier);
    await expectLater(
      dl.download(model, freeStorageBytes: () async => 10).toList(),
      throwsA(isA<ModelException>().having((e) => e.code, 'code', 'no_space')),
    );
    await server.close(force: true);
  });

  test('échec du contrôle : le fichier est supprimé', () async {
    final server = await serve(List<int>.filled(1000, 1));
    final dl = ModelDownloader(
      store: store,
      clientFactory: clientFor(server),
      verifier: (m, p) async => throw ModelException('checksum', 'x'),
    );
    await expectLater(
      dl.download(model, freeStorageBytes: () async => 1 << 30).toList(),
      throwsA(isA<ModelException>()),
    );
    expect(store.isInstalled(model), isFalse);
    expect(store.partFile(model).existsSync(), isFalse);
    await server.close(force: true);
  });

  test('suppression du modèle et du partiel', () {
    store.directory.createSync(recursive: true);
    store.file(model).writeAsBytesSync([1, 2, 3]);
    store.partFile(model).writeAsBytesSync([1]);
    expect(store.usedBytes(), 4);
    store.delete(model);
    expect(store.usedBytes(), 0);
  });
}
