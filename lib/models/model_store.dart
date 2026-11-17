import 'dart:io';

import 'model_catalog.dart';

/// Fichiers des modèles installés, dans le dossier privé de l'application.
class ModelStore {
  ModelStore(this.filesDir);

  final String filesDir;

  Directory get directory => Directory('$filesDir/models');

  File file(WhisperModel model) => File('${directory.path}/${model.fileName}');

  /// Fichier de téléchargement en cours (reprise possible).
  File partFile(WhisperModel model) => File('${directory.path}/${model.fileName}.part');

  String pathFor(WhisperModel model) => file(model).path;

  bool isInstalled(WhisperModel model) {
    final f = file(model);
    return f.existsSync() && f.lengthSync() > 0;
  }

  /// Octets déjà téléchargés d'un téléchargement interrompu.
  int partialBytes(WhisperModel model) {
    final f = partFile(model);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  List<WhisperModel> installedModels() {
    return kModelCatalog.where(isInstalled).toList();
  }

  /// Supprime le modèle et son téléchargement partiel.
  void delete(WhisperModel model) {
    final f = file(model);
    if (f.existsSync()) f.deleteSync();
    final p = partFile(model);
    if (p.existsSync()) p.deleteSync();
  }

  /// Espace total utilisé par les modèles (fichiers complets et partiels).
  int usedBytes() {
    final dir = directory;
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }
}
