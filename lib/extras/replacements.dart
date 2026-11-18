import 'dart:convert';
import 'dart:io';

import '../transcription/transcript.dart';

/// Une règle du dictionnaire de remplacement (noms propres, termes locaux...).
class Replacement {
  const Replacement({required this.from, required this.to, this.matchCase = false});

  final String from;
  final String to;

  /// Vrai : « Kindu » ne remplace pas « kindu ».
  final bool matchCase;

  Map<String, Object?> toJson() => <String, Object?>{'from': from, 'to': to, 'matchCase': matchCase};

  static Replacement fromJson(Map<String, Object?> json) => Replacement(
        from: json['from'] as String,
        to: json['to'] as String,
        matchCase: (json['matchCase'] as bool?) ?? false,
      );
}

bool _isWordChar(int unit) {
  final ch = String.fromCharCode(unit);
  return RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
}

/// Applique les règles à un texte, sur des mots entiers (« Kin » ne change pas « Kindu »).
/// Les règles sont appliquées dans l'ordre ; une règle vide est ignorée.
String applyReplacements(String text, List<Replacement> rules) {
  var out = text;
  for (final rule in rules) {
    if (rule.from.trim().isEmpty) continue;
    final pattern = RegExp(
      RegExp.escape(rule.from.trim()),
      caseSensitive: rule.matchCase,
      unicode: true,
    );
    final buffer = StringBuffer();
    var last = 0;
    for (final m in pattern.allMatches(out)) {
      final before = m.start > 0 ? out.codeUnitAt(m.start - 1) : -1;
      final after = m.end < out.length ? out.codeUnitAt(m.end) : -1;
      final startsWord = _isWordChar(rule.from.trim().codeUnitAt(0));
      final endsWord = _isWordChar(rule.from.trim().codeUnitAt(rule.from.trim().length - 1));
      final leftOk = !startsWord || before < 0 || !_isWordChar(before);
      final rightOk = !endsWord || after < 0 || !_isWordChar(after);
      if (leftOk && rightOk) {
        buffer.write(out.substring(last, m.start));
        buffer.write(rule.to);
        last = m.end;
      }
    }
    buffer.write(out.substring(last));
    out = buffer.toString();
  }
  return out;
}

List<Segment> applyReplacementsToSegments(List<Segment> segments, List<Replacement> rules) {
  if (rules.isEmpty) return segments;
  return segments.map((s) => s.copyWith(text: applyReplacements(s.text, rules))).toList();
}

/// Dictionnaire enregistré dans un fichier JSON.
class ReplacementStore {
  ReplacementStore(this.path);

  final String path;

  List<Replacement> load() {
    final f = File(path);
    if (!f.existsSync()) return <Replacement>[];
    try {
      final list = jsonDecode(f.readAsStringSync()) as List<Object?>;
      return list.map((e) => Replacement.fromJson((e as Map).cast<String, Object?>())).toList();
    } on FormatException {
      return <Replacement>[];
    } on TypeError {
      return <Replacement>[];
    }
  }

  void save(List<Replacement> rules) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(jsonEncode(rules.map((r) => r.toJson()).toList()), flush: true);
    tmp.renameSync(path);
  }
}
