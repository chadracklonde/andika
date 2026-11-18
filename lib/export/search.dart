import '../storage/job.dart';
import '../transcription/transcript.dart';

/// Un résultat de recherche dans un texte.
class SearchHit {
  const SearchHit({required this.segmentIndex, required this.start, required this.end});

  final int segmentIndex;

  /// Position dans le texte du segment (indices de caractères).
  final int start;
  final int end;
}

/// Retire les accents et la casse pour que « ete » trouve « Été ». Les
/// remplacements gardent la même longueur, donc les positions restent valables.
String foldForSearch(String input) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoAAAAAACEEEEIIIINOOOOOUUUUY';
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    final ch = String.fromCharCode(unit);
    final i = from.indexOf(ch);
    buffer.write((i >= 0 ? to[i] : ch).toLowerCase());
  }
  return buffer.toString();
}

/// Cherche [query] dans tous les segments, sans tenir compte des accents ni de la casse.
List<SearchHit> searchSegments(List<Segment> segments, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return <SearchHit>[];
  final hits = <SearchHit>[];
  for (var i = 0; i < segments.length; i++) {
    final text = foldForSearch(segments[i].text);
    var from = 0;
    while (true) {
      final at = text.indexOf(q, from);
      if (at < 0) break;
      hits.add(SearchHit(segmentIndex: i, start: at, end: at + q.length));
      from = at + q.length;
    }
  }
  return hits;
}

/// Un résultat dans l'historique : une transcription, un segment et un extrait.
class HistoryHit {
  const HistoryHit({
    required this.job,
    required this.segmentIndex,
    required this.startMs,
    required this.before,
    required this.match,
    required this.after,
  });

  final Job job;

  /// -1 quand c'est le titre qui correspond.
  final int segmentIndex;
  final int startMs;

  /// Extrait autour du passage trouvé : texte avant, passage, texte après.
  final String before;
  final String match;
  final String after;
}

/// Cherche [query] dans les titres et les textes de toutes les transcriptions.
/// [load] fournit les segments d'une transcription. Les plus récentes passent d'abord
/// (l'ordre de [jobs] est conservé) ; la recherche s'arrête à [maxHits] résultats.
List<HistoryHit> searchHistory(
  List<Job> jobs,
  List<Segment> Function(String jobId) load,
  String query, {
  int maxHits = 200,
  int context = 40,
}) {
  final q = foldForSearch(query.trim());
  if (q.length < 2) return <HistoryHit>[];
  final hits = <HistoryHit>[];
  for (final job in jobs) {
    if (hits.length >= maxHits) break;
    if (foldForSearch(job.title).contains(q)) {
      hits.add(HistoryHit(
        job: job,
        segmentIndex: -1,
        startMs: 0,
        before: '',
        match: job.title,
        after: '',
      ));
    }
    final segments = load(job.id);
    for (var i = 0; i < segments.length && hits.length < maxHits; i++) {
      final folded = foldForSearch(segments[i].text);
      // Cas rare où la mise en minuscules change la longueur : l'extrait est alors sans accents.
      final text = folded.length == segments[i].text.length ? segments[i].text : folded;
      final at = folded.indexOf(q);
      if (at < 0) continue;
      final from = at - context < 0 ? 0 : at - context;
      final to = at + q.length + context > text.length ? text.length : at + q.length + context;
      hits.add(HistoryHit(
        job: job,
        segmentIndex: i,
        startMs: segments[i].startMs,
        before: (from > 0 ? '…' : '') + text.substring(from, at),
        match: text.substring(at, at + q.length),
        after: text.substring(at + q.length, to) + (to < text.length ? '…' : ''),
      ));
    }
  }
  return hits;
}
