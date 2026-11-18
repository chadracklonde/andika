import 'dart:convert';
import 'dart:io';

/// Langues de transcription proposées (code Whisper, nom dans sa propre langue).
class TranscriptionLanguage {
  const TranscriptionLanguage(this.code, this.name, {this.limitedQuality = false});

  final String code;
  final String name;

  /// Langue peu représentée dans l'entraînement de Whisper : qualité limitée.
  final bool limitedQuality;
}

const List<TranscriptionLanguage> kTranscriptionLanguages = <TranscriptionLanguage>[
  TranscriptionLanguage('auto', 'Auto'),
  TranscriptionLanguage('fr', 'Français'),
  TranscriptionLanguage('en', 'English'),
  TranscriptionLanguage('sw', 'Kiswahili', limitedQuality: true),
  TranscriptionLanguage('ln', 'Lingála', limitedQuality: true),
  TranscriptionLanguage('pt', 'Português'),
  TranscriptionLanguage('es', 'Español'),
  TranscriptionLanguage('ar', 'العربية'),
];

bool isLimitedQuality(String code) {
  for (final l in kTranscriptionLanguages) {
    if (l.code == code) return l.limitedQuality;
  }
  return false;
}

/// Réglages de l'application.
class Settings {
  const Settings({
    this.uiLanguage = 'system',
    this.transcriptionLanguage = 'auto',
    this.modelId = 'base',
    this.skipSilence = false,
    this.exportTimestamps = false,
  });

  /// `system`, `fr` ou `en`.
  final String uiLanguage;
  final String transcriptionLanguage;
  final String modelId;
  final bool skipSilence;
  final bool exportTimestamps;

  Settings copyWith({
    String? uiLanguage,
    String? transcriptionLanguage,
    String? modelId,
    bool? skipSilence,
    bool? exportTimestamps,
  }) =>
      Settings(
        uiLanguage: uiLanguage ?? this.uiLanguage,
        transcriptionLanguage: transcriptionLanguage ?? this.transcriptionLanguage,
        modelId: modelId ?? this.modelId,
        skipSilence: skipSilence ?? this.skipSilence,
        exportTimestamps: exportTimestamps ?? this.exportTimestamps,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'uiLanguage': uiLanguage,
        'transcriptionLanguage': transcriptionLanguage,
        'modelId': modelId,
        'skipSilence': skipSilence,
        'exportTimestamps': exportTimestamps,
      };

  static Settings fromJson(Map<String, Object?> json) => Settings(
        uiLanguage: (json['uiLanguage'] as String?) ?? 'system',
        transcriptionLanguage: (json['transcriptionLanguage'] as String?) ?? 'auto',
        modelId: (json['modelId'] as String?) ?? 'base',
        skipSilence: (json['skipSilence'] as bool?) ?? false,
        exportTimestamps: (json['exportTimestamps'] as bool?) ?? false,
      );
}

class SettingsStore {
  SettingsStore(this.path);

  final String path;

  Settings load() {
    final f = File(path);
    if (!f.existsSync()) return const Settings();
    try {
      return Settings.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
    } on FormatException {
      return const Settings();
    } on TypeError {
      return const Settings();
    }
  }

  void save(Settings settings) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(jsonEncode(settings.toJson()), flush: true);
    tmp.renameSync(path);
  }
}

/// Nombre de fils de calcul : la moitié des cœurs, entre 2 et 4 (garde le téléphone fluide).
int defaultThreads(int processors) {
  final half = processors ~/ 2;
  if (half < 2) return 2;
  if (half > 4) return 4;
  return half;
}
