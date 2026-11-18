/// Un enregistrement fait avec le dictaphone d'Andika.
class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.sizeBytes,
    this.markers = const <int>[],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final int sizeBytes;

  /// Repères posés pendant l'enregistrement (instants en millisecondes, du plus ancien au plus récent).
  final List<int> markers;

  Recording copyWith({String? title, int? durationMs, int? sizeBytes}) => Recording(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        durationMs: durationMs ?? this.durationMs,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        markers: markers,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        if (markers.isNotEmpty) 'markers': markers,
      };

  static Recording fromJson(Map<String, Object?> json) => Recording(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        markers: ((json['markers'] as List<Object?>?) ?? const <Object?>[])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
      );
}

/// Date courte en heure locale, « 18/11 11:30 » (pour les titres par défaut).
String formatShortDate(DateTime utc) {
  final d = utc.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
}

/// Chronomètre précis « mm:ss,cc » (minutes, secondes, centièmes), comme sur un dictaphone.
String formatPrecise(int ms) {
  if (ms < 0) ms = 0;
  String p(int v) => v.toString().padLeft(2, '0');
  final m = ms ~/ 60000;
  final sec = (ms % 60000) ~/ 1000;
  final cs = (ms % 1000) ~/ 10;
  return '${p(m)}:${p(sec)},${p(cs)}';
}
