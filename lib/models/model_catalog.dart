/// Adresse de téléchargement des modèles au format ggml de whisper.cpp.
const String kModelBaseUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

/// Modèle proposé par défaut (voir docs/DECISIONS.md).
const String kRecommendedModelId = 'base';

const int _mib = 1024 * 1024;
const int _gb = 1000 * 1000 * 1000;

/// Un modèle Whisper téléchargeable.
class WhisperModel {
  const WhisperModel({
    required this.id,
    required this.label,
    required this.fileName,
    required this.approxBytes,
    required this.sha1,
    required this.minRamBytes,
    required this.comfortRamBytes,
    required this.speedRating,
    required this.qualityRating,
    this.quantized = false,
    this.experimental = false,
  });

  final String id;
  final String label;
  final String fileName;

  /// Taille approximative en octets (pour l'affichage et le contrôle d'espace).
  final int approxBytes;

  /// Somme de contrôle SHA-1 publiée par le projet whisper.cpp, ou null quand
  /// elle n'est pas publiée (le fichier est alors contrôlé par son en-tête).
  final String? sha1;

  /// En dessous de cette mémoire totale, le modèle est bloqué.
  final int minRamBytes;

  /// En dessous de cette mémoire totale, un avertissement est affiché.
  final int comfortRamBytes;

  /// Vitesse et qualité relatives, de 1 (faible) à 5 (élevée).
  final int speedRating;
  final int qualityRating;

  final bool quantized;

  /// Très lourd : réservé aux téléphones puissants, sans garantie.
  final bool experimental;

  String get url => '$kModelBaseUrl/$fileName';
}

/// Les modèles de la V1. Les seuils de mémoire sont des valeurs de départ prudentes
/// à ajuster après des mesures sur de vrais téléphones (docs/MESURES.md). La
/// mémoire totale annoncée par Android est un peu inférieure à la mémoire vendue
/// (un téléphone « 4 Go » annonce environ 3,6 à 3,9 Go).
const List<WhisperModel> kModelCatalog = <WhisperModel>[
  WhisperModel(
    id: 'tiny',
    label: 'Tiny',
    fileName: 'ggml-tiny.bin',
    approxBytes: 75 * _mib,
    sha1: 'bd577a113a864445d4c299885e0cb97d4ba92b5f',
    minRamBytes: 1500 * 1000 * 1000,
    comfortRamBytes: 2 * _gb,
    speedRating: 5,
    qualityRating: 1,
  ),
  WhisperModel(
    id: 'base',
    label: 'Base',
    fileName: 'ggml-base.bin',
    approxBytes: 142 * _mib,
    sha1: '465707469ff3a37a2b9b8d8f89f2f99de7299dac',
    minRamBytes: 2 * _gb,
    comfortRamBytes: 3 * _gb,
    speedRating: 4,
    qualityRating: 2,
  ),
  WhisperModel(
    id: 'base-q5_1',
    label: 'Base (léger)',
    fileName: 'ggml-base-q5_1.bin',
    approxBytes: 57 * _mib,
    sha1: null,
    minRamBytes: 2 * _gb,
    comfortRamBytes: 3 * _gb,
    speedRating: 4,
    qualityRating: 2,
    quantized: true,
  ),
  WhisperModel(
    id: 'small',
    label: 'Small',
    fileName: 'ggml-small.bin',
    approxBytes: 466 * _mib,
    sha1: '55356645c2b361a969dfd0ef2c5a50d530afd8d5',
    minRamBytes: 3 * _gb,
    comfortRamBytes: 5500 * 1000 * 1000,
    speedRating: 2,
    qualityRating: 4,
  ),
  WhisperModel(
    id: 'small-q5_1',
    label: 'Small (léger)',
    fileName: 'ggml-small-q5_1.bin',
    approxBytes: 181 * _mib,
    sha1: null,
    minRamBytes: 3 * _gb,
    comfortRamBytes: 4500 * 1000 * 1000,
    speedRating: 3,
    qualityRating: 4,
    quantized: true,
  ),
  WhisperModel(
    id: 'medium',
    label: 'Medium',
    fileName: 'ggml-medium.bin',
    approxBytes: 1536 * _mib,
    sha1: 'fd9727b6e1217c2f614f9b698455c4ffd82463b4',
    minRamBytes: 5500 * 1000 * 1000,
    comfortRamBytes: 7500 * 1000 * 1000,
    speedRating: 1,
    qualityRating: 5,
    experimental: true,
  ),
];

/// Trouve un modèle par son identifiant, ou null.
WhisperModel? modelById(String id) {
  for (final model in kModelCatalog) {
    if (model.id == id) return model;
  }
  return null;
}

/// Adéquation d'un modèle à la mémoire du téléphone.
enum ModelFit { good, tight, tooHeavy }

/// [totalRamBytes] <= 0 signifie « inconnue » : on ne bloque rien.
ModelFit modelFit(WhisperModel model, int totalRamBytes) {
  if (totalRamBytes <= 0) return ModelFit.good;
  if (totalRamBytes < model.minRamBytes) return ModelFit.tooHeavy;
  if (totalRamBytes < model.comfortRamBytes) return ModelFit.tight;
  return ModelFit.good;
}

/// Meilleur modèle à proposer d'emblée selon la mémoire.
WhisperModel recommendedModel(int totalRamBytes) {
  final base = modelById(kRecommendedModelId)!;
  if (modelFit(base, totalRamBytes) == ModelFit.tooHeavy) {
    return modelById('tiny')!;
  }
  return base;
}
