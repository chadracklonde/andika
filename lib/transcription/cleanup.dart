import 'transcript.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), ' ').trim();

/// Whisper répète parfois la même phrase en boucle sur du bruit ou du silence.
/// Garde au plus [maxRepeats] segments consécutifs identiques (sans tenir compte
/// de la casse ni de la ponctuation) et retire les segments vides.
List<Segment> collapseRepeats(List<Segment> segments, {int maxRepeats = 2}) {
  final out = <Segment>[];
  String? last;
  var run = 0;
  for (final s in segments) {
    final key = _norm(s.text);
    if (key.isEmpty) continue;
    if (key == last) {
      run++;
      if (run > maxRepeats) continue;
    } else {
      last = key;
      run = 1;
    }
    out.add(s);
  }
  return out;
}

/// Phrases que Whisper « invente » sur du silence ou de la musique, héritées des
/// sous-titres vus à l'entraînement. Un segment qui en contient une est retiré.
final List<String> _stockPhrases = <String>[
  "Sous-titrage ST' 501",
  "Sous-titres réalisés par la communauté d'Amara.org",
  'Sous-titrage Société Radio-Canada',
  'Sous-titrage FR',
  "Merci d'avoir regardé cette vidéo",
  "Merci d'avoir regardé la vidéo",
  "N'oubliez pas de vous abonner",
  'Abonnez-vous à la chaîne',
  'Thanks for watching',
  'Thank you for watching',
  'Subtitles by the Amara.org community',
  'Please subscribe to my channel',
  "Don't forget to subscribe",
].map(_norm).toList();

/// Marqueurs de bruit seuls dans un segment : « [Musique] », « (Applaudissements) », « ♪ ».
final RegExp _noiseMarker = RegExp(
  r'^[\[\(\*♪♫\s]*(musique|music|applaudissements|applause|silence|rires|laughter)?[\]\)\*♪♫\s.\-–—…]*$',
  caseSensitive: false,
);

/// Vrai si le segment est probablement une « hallucination » sur du silence.
bool isHallucination(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (_noiseMarker.hasMatch(t)) return true;
  final key = _norm(t);
  if (key.isEmpty) return true;
  for (final phrase in _stockPhrases) {
    if (key.contains(phrase)) return true;
  }
  return false;
}

/// Réduit une boucle à l'intérieur d'un même segment (« Merci Merci Merci Merci Merci »)
/// à [keep] répétitions, dès qu'un groupe de 1 à [maxPeriod] mots se répète
/// [minRepeats] fois de suite ou plus. Un texte sans boucle est rendu tel quel.
String collapseLoops(String text, {int minRepeats = 4, int keep = 2, int maxPeriod = 8}) {
  final tokens = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final keys = tokens.map(_norm).toList();
  final n = tokens.length;
  if (n < minRepeats) return text;
  final out = <String>[];
  var changed = false;
  var i = 0;
  while (i < n) {
    var bestPeriod = 0;
    var bestReps = 0;
    for (var p = 1; p <= maxPeriod; p++) {
      if (i + p * minRepeats > n) break;
      var reps = 1;
      while (i + (reps + 1) * p <= n) {
        var same = true;
        for (var k = 0; k < p; k++) {
          if (keys[i + k] != keys[i + reps * p + k]) {
            same = false;
            break;
          }
        }
        if (!same) break;
        reps++;
      }
      if (reps >= minRepeats && reps * p > bestReps * bestPeriod) {
        bestPeriod = p;
        bestReps = reps;
      }
    }
    if (bestPeriod > 0) {
      out.addAll(tokens.sublist(i, i + keep * bestPeriod));
      i += bestReps * bestPeriod;
      changed = true;
    } else {
      out.add(tokens[i]);
      i++;
    }
  }
  return changed ? out.join(' ') : text;
}

/// Nettoyage complet appliqué à la fin d'une transcription : retire les phrases
/// parasites, réduit les boucles dans un segment, puis les répétitions entre segments.
List<Segment> cleanTranscript(List<Segment> segments) {
  final kept = <Segment>[];
  for (final s in segments) {
    if (isHallucination(s.text)) continue;
    final collapsed = collapseLoops(s.text);
    kept.add(collapsed == s.text ? s : s.copyWith(text: collapsed));
  }
  return collapseRepeats(kept);
}
