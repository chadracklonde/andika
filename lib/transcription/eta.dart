/// Estimation du temps restant, à partir du rythme observé sur cette tâche.
class EtaEstimator {
  EtaEstimator({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _start;
  int _startDone = 0;

  /// Morceaux nécessaires avant de donner une estimation (la première est trop
  /// instable : chargement du modèle, morceaux de durées différentes).
  static const int minSamples = 2;

  /// À appeler à chaque progression. [done] : morceaux terminés, [total] : à faire.
  /// Retourne le temps restant, ou null tant que l'estimation n'est pas fiable.
  Duration? update(int done, int total) {
    final now = _clock();
    if (_start == null) {
      _start = now;
      _startDone = done;
      return null;
    }
    final newlyDone = done - _startDone;
    if (newlyDone < minSamples || total <= done) return null;
    final elapsed = now.difference(_start!);
    if (elapsed.inMilliseconds <= 0) return null;
    final perChunk = elapsed.inMilliseconds / newlyDone;
    return Duration(milliseconds: (perChunk * (total - done)).round());
  }
}

/// « 5 min », « 1 h 05 », « moins d'une minute » sous forme de (heures, minutes).
({int hours, int minutes}) splitEta(Duration d) {
  final totalMinutes = (d.inSeconds / 60).ceil();
  return (hours: totalMinutes ~/ 60, minutes: totalMinutes % 60);
}
