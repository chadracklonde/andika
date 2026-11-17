import 'dart:convert';
import 'dart:io';

import 'transcript.dart';

/// Résultat d'un morceau déjà transcrit.
class ChunkRecord {
  const ChunkRecord({required this.index, required this.language, required this.segments});

  final int index;
  final String language;
  final List<Segment> segments;
}

/// Journal des morceaux transcrits : un fichier JSON par ligne, une ligne par
/// morceau, ajoutée dès que le morceau est terminé. Après une interruption
/// (arrêt de l'application, batterie), la transcription reprend au premier morceau
/// absent du journal. Une dernière ligne tronquée est ignorée.
class SegmentLog {
  SegmentLog(this.path);

  final String path;

  File get _file => File(path);

  bool get exists => _file.existsSync();

  void append(ChunkRecord record) {
    final line = jsonEncode(<String, Object?>{
      'c': record.index,
      'l': record.language,
      'g': record.segments.map((s) => s.toJson()).toList(),
    });
    _file.parent.createSync(recursive: true);
    final raf = _file.openSync(mode: FileMode.append);
    try {
      raf.writeStringSync('$line\n');
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
  }

  /// Lit tous les morceaux valides, dans l'ordre d'écriture.
  List<ChunkRecord> read() {
    if (!exists) return <ChunkRecord>[];
    final records = <ChunkRecord>[];
    for (final line in _file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        final map = jsonDecode(line) as Map<String, Object?>;
        final segs = (map['g'] as List<Object?>)
            .map((e) => Segment.fromJson((e as Map).cast<String, Object?>()))
            .toList();
        records.add(ChunkRecord(
          index: (map['c'] as num).toInt(),
          language: (map['l'] as String?) ?? '',
          segments: segs,
        ));
      } on FormatException {
        break; // ligne tronquée : on s'arrête là
      } on TypeError {
        break;
      }
    }
    return records;
  }

  /// Indices des morceaux déjà terminés.
  Set<int> completedChunks() => read().map((r) => r.index).toSet();

  /// Tous les segments, triés par temps de début.
  List<Segment> allSegments() {
    final all = <Segment>[];
    for (final r in read()) {
      all.addAll(r.segments);
    }
    all.sort((a, b) => a.startMs.compareTo(b.startMs));
    return all;
  }

  /// Langue détectée la plus fréquente, ou vide.
  String dominantLanguage() {
    final counts = <String, int>{};
    for (final r in read()) {
      if (r.language.isEmpty) continue;
      counts[r.language] = (counts[r.language] ?? 0) + 1;
    }
    String best = '';
    var bestCount = 0;
    counts.forEach((lang, n) {
      if (n > bestCount) {
        best = lang;
        bestCount = n;
      }
    });
    return best;
  }

  void delete() {
    if (exists) _file.deleteSync();
  }
}
