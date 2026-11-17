/// Un segment de texte, avec des temps absolus (en ms) dans l'enregistrement.
class Segment {
  const Segment({required this.startMs, required this.endMs, required this.text});

  final int startMs;
  final int endMs;
  final String text;

  Segment copyWith({String? text}) =>
      Segment(startMs: startMs, endMs: endMs, text: text ?? this.text);

  Map<String, Object?> toJson() => <String, Object?>{'s': startMs, 'e': endMs, 't': text};

  static Segment fromJson(Map<String, Object?> json) => Segment(
        startMs: (json['s'] as num).toInt(),
        endMs: (json['e'] as num).toInt(),
        text: json['t'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is Segment && other.startMs == startMs && other.endMs == endMs && other.text == text;

  @override
  int get hashCode => Object.hash(startMs, endMs, text);

  @override
  String toString() => 'Segment($startMs–$endMs, $text)';
}

/// Réglages d'une transcription.
class TranscriptionOptions {
  const TranscriptionOptions({
    required this.modelPath,
    this.language = 'auto',
    this.threads = 4,
    this.skipSilence = false,
  });

  final String modelPath;

  /// Code de langue Whisper (`fr`, `en`, `sw`, `ln`...) ou `auto`.
  final String language;
  final int threads;
  final bool skipSilence;
}
