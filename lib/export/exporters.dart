import '../transcription/transcript.dart';

/// Formats d'export de la V1.
enum ExportFormat { txt, srt }

/// « 00:01:05,320 » (format SRT).
String srtTime(int ms) {
  if (ms < 0) ms = 0;
  String p(int v, int w) => v.toString().padLeft(w, '0');
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return '${p(h, 2)}:${p(m, 2)}:${p(s, 2)},${p(ms % 1000, 3)}';
}

/// « 1:05 » ou « 1:02:05 » (affichage et texte horodaté).
String clockTime(int ms) {
  if (ms < 0) ms = 0;
  String p(int v) => v.toString().padLeft(2, '0');
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
}

/// Texte brut. Avec [timestamps], chaque segment est précédé de son heure et
/// séparé par un saut de ligne ; sinon les segments forment un texte continu.
String toPlainText(List<Segment> segments, {bool timestamps = false}) {
  final kept = segments.where((s) => s.text.trim().isNotEmpty).toList();
  if (timestamps) {
    return kept.map((s) => '[${clockTime(s.startMs)}] ${s.text.trim()}').join('\n');
  }
  return kept.map((s) => s.text.trim()).join(' ');
}

/// Sous-titres SRT : numérotés de 1, fin toujours après le début et jamais après
/// le début du segment suivant.
String toSrt(List<Segment> segments) {
  final kept = segments.where((s) => s.text.trim().isNotEmpty).toList();
  final buffer = StringBuffer();
  for (var i = 0; i < kept.length; i++) {
    final s = kept[i];
    var end = s.endMs;
    if (end <= s.startMs) end = s.startMs + 500;
    if (i + 1 < kept.length && end > kept[i + 1].startMs && kept[i + 1].startMs > s.startMs) {
      end = kept[i + 1].startMs;
    }
    buffer
      ..writeln(i + 1)
      ..writeln('${srtTime(s.startMs)} --> ${srtTime(end)}')
      ..writeln(s.text.trim())
      ..writeln();
  }
  return buffer.toString();
}

String exportExtension(ExportFormat f) => f == ExportFormat.srt ? 'srt' : 'txt';

String exportMime(ExportFormat f) => f == ExportFormat.srt ? 'application/x-subrip' : 'text/plain';

/// Nom de fichier sûr (sans caractères interdits ni espaces multiples).
String safeFileName(String title, {String fallback = 'transcription'}) {
  var s = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > 80) s = s.substring(0, 80).trim();
  s = s.replaceAll(RegExp(r'^\.+'), '');
  return s.isEmpty ? fallback : s;
}

String exportContent(List<Segment> segments, ExportFormat format, {bool timestamps = false}) {
  return format == ExportFormat.srt ? toSrt(segments) : toPlainText(segments, timestamps: timestamps);
}
