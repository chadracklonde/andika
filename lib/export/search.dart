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
