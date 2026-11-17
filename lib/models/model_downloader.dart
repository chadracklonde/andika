import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../engine/native_lib.dart';
import 'model_catalog.dart';
import 'model_store.dart';

/// Erreur de téléchargement. [code] : `network`, `http`, `no_space`, `incomplete`,
/// `invalid`, `checksum`, `io`, `cancelled`.
class ModelException implements Exception {
  ModelException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ModelException($code): $message';
}

/// Permet d'interrompre un téléchargement (le fichier partiel est conservé).
class DownloadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class DownloadProgress {
  const DownloadProgress({required this.receivedBytes, required this.totalBytes, this.verifying = false});

  final int receivedBytes;

  /// Taille totale, -1 si inconnue.
  final int totalBytes;

  /// Vrai pendant le contrôle du fichier, une fois tout reçu.
  final bool verifying;

  double? get fraction => totalBytes > 0 ? receivedBytes / totalBytes : null;
}

/// Contrôle un fichier téléchargé ; lève [ModelException] s'il est incorrect.
typedef ModelVerifier = Future<void> Function(WhisperModel model, String path);

/// Contrôle par défaut : en-tête ggml puis SHA-1 si connu (dans un isolate, car
/// le calcul sur un gros modèle prend quelques secondes).
Future<void> verifyModelFile(WhisperModel model, String path) async {
  final expected = model.sha1;
  final problem = await Isolate.run<String?>(() {
    final lib = NativeLib.open();
    if (!lib.checkModel(path)) return 'invalid';
    if (expected != null && lib.sha1File(path) != expected) return 'checksum';
    return null;
  });
  if (problem == 'invalid') {
    throw ModelException('invalid', 'Le fichier téléchargé n\'est pas un modèle valide');
  }
  if (problem == 'checksum') {
    throw ModelException('checksum', 'La somme de contrôle du modèle ne correspond pas');
  }
}

/// Marge d'espace libre exigée en plus de la taille du modèle.
const int kDownloadSpareBytes = 50 * 1024 * 1024;

/// Téléchargement avec reprise, redirections suivies à la main (pour conserver
/// l'en-tête Range) et contrôle final.
class ModelDownloader {
  ModelDownloader({
    required this.store,
    HttpClient Function()? clientFactory,
    ModelVerifier? verifier,
  })  : _clientFactory = clientFactory ?? HttpClient.new,
        _verifier = verifier ?? verifyModelFile;

  final ModelStore store;
  final HttpClient Function() _clientFactory;
  final ModelVerifier _verifier;

  /// Télécharge [model]. Le flux émet la progression et se termine quand le
  /// modèle est installé. Les erreurs sont des [ModelException].
  Stream<DownloadProgress> download(
    WhisperModel model, {
    required Future<int> Function() freeStorageBytes,
    DownloadCancelToken? cancelToken,
  }) async* {
    if (store.isInstalled(model)) {
      final size = store.file(model).lengthSync();
      yield DownloadProgress(receivedBytes: size, totalBytes: size);
      return;
    }
    final part = store.partFile(model);
    store.directory.createSync(recursive: true);
    var existing = part.existsSync() ? part.lengthSync() : 0;

    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 20);
    client.userAgent = 'Andika';
    try {
      var response = await _open(client, Uri.parse(model.url), existing);
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // Le partiel ne correspond plus au fichier distant : on repart de zéro.
        await response.drain<void>();
        if (part.existsSync()) part.deleteSync();
        existing = 0;
        response = await _open(client, Uri.parse(model.url), 0);
      }
      var offset = existing;
      var total = -1;
      if (response.statusCode == HttpStatus.partialContent) {
        total = _totalFromContentRange(response.headers.value(HttpHeaders.contentRangeHeader));
      } else if (response.statusCode == HttpStatus.ok) {
        offset = 0; // le serveur renvoie tout le fichier
        total = response.contentLength;
      } else {
        await response.drain<void>();
        throw ModelException('http', 'Le serveur a répondu ${response.statusCode}');
      }

      final expectedTotal = total > 0 ? total : model.approxBytes;
      final free = await freeStorageBytes();
      if (free < expectedTotal - offset + kDownloadSpareBytes) {
        await response.drain<void>();
        throw ModelException('no_space', 'Espace de stockage insuffisant');
      }

      var received = offset;
      yield DownloadProgress(receivedBytes: received, totalBytes: total);
      final raf = part.openSync(mode: offset > 0 ? FileMode.append : FileMode.write);
      try {
        var lastEmit = DateTime.now();
        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          if (cancelToken != null && cancelToken.isCancelled) {
            throw ModelException('cancelled', 'Téléchargement annulé');
          }
          raf.writeFromSync(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmit) >= const Duration(milliseconds: 300)) {
            lastEmit = now;
            yield DownloadProgress(receivedBytes: received, totalBytes: total);
          }
        }
      } finally {
        raf.closeSync();
      }

      if (total > 0 && received != total) {
        throw ModelException('incomplete', 'Téléchargement incomplet');
      }
      yield DownloadProgress(receivedBytes: received, totalBytes: total, verifying: true);
      try {
        await _verifier(model, part.path);
      } on ModelException {
        if (part.existsSync()) part.deleteSync();
        rethrow;
      }
      part.renameSync(store.file(model).path);
      yield DownloadProgress(receivedBytes: received, totalBytes: received);
    } on ModelException {
      rethrow;
    } on TimeoutException {
      throw ModelException('network', 'Connexion interrompue');
    } on SocketException catch (e) {
      throw ModelException('network', 'Réseau indisponible : ${e.message}');
    } on HandshakeException catch (e) {
      throw ModelException('network', 'Connexion sécurisée impossible : ${e.message}');
    } on HttpException catch (e) {
      throw ModelException('network', 'Erreur réseau : ${e.message}');
    } on FileSystemException catch (e) {
      throw ModelException('io', 'Erreur d\'écriture : ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri uri, int offset) async {
    var current = uri;
    for (var i = 0; i < 6; i++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw ModelException('http', 'Redirection invalide');
        }
        current = current.resolve(location);
        continue;
      }
      return response;
    }
    throw ModelException('http', 'Trop de redirections');
  }

  /// « bytes 100-999/1000 » donne 1000 ; -1 si absent ou illisible.
  static int _totalFromContentRange(String? value) {
    if (value == null) return -1;
    final slash = value.lastIndexOf('/');
    if (slash < 0) return -1;
    return int.tryParse(value.substring(slash + 1).trim()) ?? -1;
  }
}
