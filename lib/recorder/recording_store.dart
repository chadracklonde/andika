import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../audio/wav_file.dart';
import 'recording.dart';

/// Enregistrements du dictaphone, dans le dossier privé de l'application :
///   recordings/<id>.wav    audio (WAV 16 kHz mono, comme l'audio importé)
///   recordings/<id>.json   fiche (titre, date, durée)
class RecordingStore {
  RecordingStore(this.filesDir);

  final String filesDir;

  Directory get _dir => Directory('$filesDir/recordings');

  String wavPath(String id) => '${_dir.path}/$id.wav';
  File _metaFile(String id) => File('${_dir.path}/$id.json');

  /// Identifiant unique, trié par date (heure UTC).
  String newId([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = 'rec-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    var id = stamp;
    var n = 1;
    while (File(wavPath(id)).existsSync() || _metaFile(id).existsSync()) {
      id = '$stamp-$n';
      n++;
    }
    return id;
  }

  void save(Recording r) {
    _dir.createSync(recursive: true);
    final tmp = File('${_metaFile(r.id).path}.tmp');
    tmp.writeAsStringSync(jsonEncode(r.toJson()), flush: true);
    tmp.renameSync(_metaFile(r.id).path); // écriture atomique
  }

  Recording? load(String id) {
    final f = _metaFile(id);
    if (!f.existsSync()) return null;
    try {
      return Recording.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Tous les enregistrements dont l'audio existe, le plus récent d'abord.
  List<Recording> list() {
    if (!_dir.existsSync()) return <Recording>[];
    final out = <Recording>[];
    for (final e in _dir.listSync()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final name = e.uri.pathSegments.last;
      final id = name.substring(0, name.length - '.json'.length);
      final r = load(id);
      if (r != null && File(wavPath(id)).existsSync()) out.add(r);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  void rename(Recording r, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    save(r.copyWith(title: t));
  }

  void delete(String id) {
    final w = File(wavPath(id));
    if (w.existsSync()) w.deleteSync();
    final m = _metaFile(id);
    if (m.existsSync()) m.deleteSync();
  }

  /// Espace occupé par tous les enregistrements.
  int totalBytes() {
    if (!_dir.existsSync()) return 0;
    var total = 0;
    for (final e in _dir.listSync()) {
      if (e is File && e.path.endsWith('.wav')) total += e.lengthSync();
    }
    return total;
  }

  /// Fichiers audio sans fiche (enregistrement interrompu par un arrêt brutal) :
  /// l'en-tête est réparé et une fiche est créée. [skipPath] protège un enregistrement
  /// encore en cours. Retourne les enregistrements retrouvés.
  List<Recording> recoverOrphans({required String Function(DateTime) titleFor, String? skipPath}) {
    if (!_dir.existsSync()) return <Recording>[];
    final found = <Recording>[];
    for (final e in _dir.listSync()) {
      if (e is! File || !e.path.endsWith('.wav')) continue;
      if (skipPath != null && e.path == skipPath) continue;
      final name = e.uri.pathSegments.last;
      final id = name.substring(0, name.length - '.wav'.length);
      if (_metaFile(id).existsSync()) continue;
      final durationMs = repairWavHeader(e.path);
      if (durationMs <= 0) {
        e.deleteSync(); // aucun son exploitable
        continue;
      }
      final created = e.lastModifiedSync().toUtc();
      final r = Recording(
        id: id,
        title: titleFor(created),
        createdAt: created,
        durationMs: durationMs,
        sizeBytes: e.lengthSync(),
      );
      save(r);
      found.add(r);
    }
    return found;
  }
}

/// Remet l'en-tête d'un WAV Andika en accord avec la taille réelle du fichier
/// (utile après un arrêt brutal, quand l'en-tête annonce moins que ce qui est écrit).
/// Si l'en-tête est déjà juste, le fichier n'est pas touché. Sinon une copie corrigée
/// remplace l'original (dart:io ne permet pas de réécrire le début d'un fichier existant
/// sans le tronquer). Retourne la durée en millisecondes, ou -1 si le fichier est inutilisable.
int repairWavHeader(String path) {
  final file = File(path);
  if (!file.existsSync()) return -1;
  final length = file.lengthSync();
  if (length < WavReader.headerSize + 2) return -1;
  // Un nombre impair d'octets (écriture coupée) : on ignore l'octet isolé.
  final samples = (length - WavReader.headerSize) ~/ 2;
  final durationMs = samples * 1000 ~/ WavReader.sampleRate;
  var declared = -1;
  try {
    declared = declaredSamples(path);
  } on FormatException {
    declared = -1;
  }
  if (declared == samples && length == WavReader.headerSize + samples * 2) return durationMs;

  final tmp = File('$path.repair');
  final src = file.openSync();
  final dst = tmp.openSync(mode: FileMode.write);
  try {
    dst.writeFromSync(WavReader.buildHeader(samples));
    src.setPositionSync(WavReader.headerSize);
    var remaining = samples * 2;
    final buffer = Uint8List(1024 * 1024);
    while (remaining > 0) {
      final want = remaining < buffer.length ? remaining : buffer.length;
      final got = src.readIntoSync(buffer, 0, want);
      if (got <= 0) break;
      dst.writeFromSync(buffer, 0, got);
      remaining -= got;
    }
    dst.flushSync();
  } finally {
    src.closeSync();
    dst.closeSync();
  }
  tmp.renameSync(path);
  return durationMs;
}

/// Lit l'en-tête (utile aux tests) : nombre d'échantillons annoncé.
int declaredSamples(String path) {
  final raf = File(path).openSync();
  try {
    final h = Uint8List(WavReader.headerSize);
    raf.readIntoSync(h);
    return WavReader.parseHeader(h);
  } finally {
    raf.closeSync();
  }
}
