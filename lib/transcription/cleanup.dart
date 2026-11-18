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
