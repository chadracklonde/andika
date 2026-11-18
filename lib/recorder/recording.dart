/// Un enregistrement fait avec le dictaphone d'Andika.
class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.sizeBytes,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final int sizeBytes;

  Recording copyWith({String? title, int? durationMs, int? sizeBytes}) => Recording(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        durationMs: durationMs ?? this.durationMs,
        sizeBytes: sizeBytes ?? this.sizeBytes,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };

  static Recording fromJson(Map<String, Object?> json) => Recording(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Date courte en heure locale, « 18/11 11:30 » (pour les titres par défaut).
String formatShortDate(DateTime utc) {
  final d = utc.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
}
