/// État d'une transcription dans l'historique.
enum JobStatus { running, interrupted, done, failed }

/// Fiche d'une transcription (le texte est dans des fichiers à part).
class Job {
  const Job({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.language,
    required this.modelId,
    required this.status,
    this.detectedLanguage = '',
    this.hasAudio = true,
    this.error,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int durationMs;

  /// Langue demandée (`auto` ou un code).
  final String language;
  final String modelId;
  final JobStatus status;

  /// Langue détectée par Whisper, vide tant qu'inconnue.
  final String detectedLanguage;

  /// Faux une fois le fichier audio supprimé pour libérer de l'espace.
  final bool hasAudio;
  final String? error;

  Job copyWith({
    String? title,
    JobStatus? status,
    String? detectedLanguage,
    bool? hasAudio,
    String? error,
    int? durationMs,
  }) =>
      Job(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        durationMs: durationMs ?? this.durationMs,
        language: language,
        modelId: modelId,
        status: status ?? this.status,
        detectedLanguage: detectedLanguage ?? this.detectedLanguage,
        hasAudio: hasAudio ?? this.hasAudio,
        error: error ?? this.error,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'language': language,
        'modelId': modelId,
        'status': status.name,
        'detectedLanguage': detectedLanguage,
        'hasAudio': hasAudio,
        if (error != null) 'error': error,
      };

  static Job fromJson(Map<String, Object?> json) => Job(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        language: (json['language'] as String?) ?? 'auto',
        modelId: (json['modelId'] as String?) ?? '',
        status: JobStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => JobStatus.failed,
        ),
        detectedLanguage: (json['detectedLanguage'] as String?) ?? '',
        hasAudio: (json['hasAudio'] as bool?) ?? true,
        error: json['error'] as String?,
      );
}
